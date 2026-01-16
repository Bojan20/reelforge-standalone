# Godot Audio System — Complete Technical Analysis

> **Analysis Date:** January 2026
> **Engine Version:** Godot 4.3+
> **Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## Executive Summary

Godot Engine provides a fully integrated audio system with an audio bus architecture inspired by professional DAW workflows. The system includes built-in effects processing, 3D spatialization with doppler support, area-based reverb zones, and procedural audio generation via AudioStreamGenerator. While simpler than middleware solutions like Wwise or FMOD, Godot's audio system is capable and accessible, with ongoing development toward more advanced DSP capabilities.

**Key Characteristics:**
- **Open source** — MIT licensed, fully accessible code
- **Bus-based mixing** — DAW-style routing and effects
- **Built-in effects** — Compressor, EQ, reverb, delay, etc.
- **3D spatialization** — Distance attenuation, doppler, directional
- **Area-based audio** — Reverb zones and bus routing
- **Procedural audio** — AudioStreamGenerator for real-time synthesis

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [AudioServer](#2-audioserver)
3. [Audio Bus System](#3-audio-bus-system)
4. [AudioStreamPlayer Nodes](#4-audiostreamplayer-nodes)
5. [Audio Stream Types](#5-audio-stream-types)
6. [Audio Effects](#6-audio-effects)
7. [3D Audio & Spatialization](#7-3d-audio--spatialization)
8. [Area-Based Audio](#8-area-based-audio)
9. [Procedural Audio](#9-procedural-audio)
10. [Audio Import Settings](#10-audio-import-settings)
11. [Performance & Optimization](#11-performance--optimization)
12. [GDScript Audio API](#12-gdscript-audio-api)
13. [Advanced Techniques](#13-advanced-techniques)
14. [Limitations & Proposals](#14-limitations--proposals)
15. [Comparison with Other Engines](#15-comparison-with-other-engines)
16. [FluxForge Integration Points](#16-fluxforge-integration-points)

---

## 1. Architecture Overview

### 1.1 System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    SCENE TREE LAYER                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │AudioStreamPlayer│  │AudioStreamPlayer│  │AudioStreamPlayer│ │
│  │     (2D)        │  │      (3D)       │  │    (Non-pos)    │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │           │
│           └────────────────────┼────────────────────┘           │
│                                ▼                                 │
├─────────────────────────────────────────────────────────────────┤
│                      AUDIO SERVER                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Audio Bus Layout                          ││
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐││
│  │  │  Music  │  │   SFX   │  │  Voice  │  │    Ambient      │││
│  │  │   Bus   │  │   Bus   │  │   Bus   │  │      Bus        │││
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────────┬────────┘││
│  │       │            │            │                │          ││
│  │       │   ┌────────┴────────────┴────────────────┘          ││
│  │       │   │                                                  ││
│  │       ▼   ▼                                                  ││
│  │  ┌────────────────────────────────────────────────────────┐ ││
│  │  │                     Master Bus                          │ ││
│  │  │  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐│ ││
│  │  │  │   EQ     │→│Compressor│→│        Limiter         ││ ││
│  │  │  └──────────┘  └──────────┘  └───────────────────────┘│ ││
│  │  └────────────────────────────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                    AUDIO DRIVER                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   WASAPI    │  │  CoreAudio  │  │    PulseAudio/ALSA      │ │
│  │  (Windows)  │  │   (macOS)   │  │       (Linux)           │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Core Components

| Component | Purpose | Description |
|-----------|---------|-------------|
| **AudioServer** | Low-level server | Manages buses, effects, output |
| **AudioStreamPlayer** | Non-positional playback | UI sounds, music |
| **AudioStreamPlayer2D** | 2D positional audio | 2D game sounds |
| **AudioStreamPlayer3D** | 3D positional audio | 3D game sounds |
| **AudioBus** | Signal path | Routing and effects chain |
| **AudioEffect** | DSP processing | Filters, dynamics, etc. |
| **AudioStream** | Audio data | WAV, OGG, MP3, procedural |
| **AudioListener3D** | 3D receiver | Camera/character ears |

### 1.3 Project Settings

```gdscript
# Project Settings → Audio
# Located in: project.godot

[audio]
# Driver selection
driver = "PulseAudio"  # or WASAPI, CoreAudio, etc.

# Buffer settings
mix_rate = 44100       # Sample rate (Hz)
output_latency = 15    # Target latency (ms)
output_latency.web = 50

# Voice limits
default_bus_layout = "res://default_bus_layout.tres"

# 2D/3D panning
enable_audio_input = false
panning_strength = 1.0
```

---

## 2. AudioServer

### 2.1 AudioServer Overview

AudioServer is Godot's singleton that manages all audio operations.

```gdscript
# AudioServer is accessed as a singleton
# Core properties and methods:

# Bus management
AudioServer.bus_count                    # Number of buses
AudioServer.get_bus_name(bus_idx)        # Get bus name
AudioServer.get_bus_index(bus_name)      # Get bus index
AudioServer.add_bus(at_position)         # Add new bus
AudioServer.remove_bus(index)            # Remove bus
AudioServer.move_bus(index, to_index)    # Reorder bus

# Bus properties
AudioServer.set_bus_volume_db(bus_idx, volume_db)
AudioServer.get_bus_volume_db(bus_idx)
AudioServer.set_bus_mute(bus_idx, mute)
AudioServer.is_bus_mute(bus_idx)
AudioServer.set_bus_solo(bus_idx, solo)
AudioServer.is_bus_solo(bus_idx)
AudioServer.set_bus_bypass_effects(bus_idx, bypass)
AudioServer.is_bus_bypassing_effects(bus_idx)

# Bus routing
AudioServer.set_bus_send(bus_idx, send_bus_name)
AudioServer.get_bus_send(bus_idx)

# Effects
AudioServer.get_bus_effect_count(bus_idx)
AudioServer.get_bus_effect(bus_idx, effect_idx)
AudioServer.add_bus_effect(bus_idx, effect, at_position)
AudioServer.remove_bus_effect(bus_idx, effect_idx)
AudioServer.swap_bus_effects(bus_idx, effect_idx, by_effect_idx)
AudioServer.set_bus_effect_enabled(bus_idx, effect_idx, enabled)
AudioServer.is_bus_effect_enabled(bus_idx, effect_idx)

# Metering
AudioServer.get_bus_peak_volume_left_db(bus_idx, channel)
AudioServer.get_bus_peak_volume_right_db(bus_idx, channel)

# System info
AudioServer.get_output_latency()         # Effective latency
AudioServer.get_mix_rate()               # Current sample rate
AudioServer.get_speaker_mode()           # Speaker configuration
AudioServer.get_time_since_last_mix()    # Time since last mix
AudioServer.get_time_to_next_mix()       # Time until next mix
```

### 2.2 Speaker Modes

```gdscript
# Supported speaker configurations
enum SpeakerMode {
    SPEAKER_MODE_STEREO,      # 2 channels
    SPEAKER_SURROUND_31,      # 3.1 channels
    SPEAKER_SURROUND_51,      # 5.1 channels
    SPEAKER_SURROUND_71       # 7.1 channels
}

# Get current mode
var mode = AudioServer.get_speaker_mode()

# Speaker mode affects:
# - How 3D audio is panned
# - Number of output channels
# - Surround sound processing
```

### 2.3 Audio Playback Tracking

```gdscript
# Get playback information
class_name AudioManager
extends Node

func get_active_playbacks() -> int:
    var count = 0
    for bus_idx in range(AudioServer.bus_count):
        # Each bus tracks active voices internally
        # Access via AudioServer signals or polling
        pass
    return count

# Monitor bus activity
func _process(_delta):
    var master_idx = AudioServer.get_bus_index("Master")
    var peak_l = AudioServer.get_bus_peak_volume_left_db(master_idx, 0)
    var peak_r = AudioServer.get_bus_peak_volume_right_db(master_idx, 0)

    # Peak values are in dB
    # -infinity = silence, 0 = full scale
    print("Peak L: %s dB, Peak R: %s dB" % [peak_l, peak_r])
```

---

## 3. Audio Bus System

### 3.1 Bus Layout

```
Audio Bus Layout (default_bus_layout.tres):

┌─────────────────────────────────────────────────────────────────┐
│                       BUS LAYOUT                                 │
│                                                                  │
│  ┌─────────┐                                                    │
│  │ Master  │ ← All buses route here by default                  │
│  │ Bus (0) │                                                    │
│  │ [EQ]    │                                                    │
│  │ [Limit] │                                                    │
│  └────▲────┘                                                    │
│       │                                                          │
│  ┌────┴────┬──────────┬──────────┬──────────┐                  │
│  │         │          │          │          │                   │
│  │ ┌───────┴┐ ┌───────┴┐ ┌───────┴┐ ┌───────┴┐                 │
│  │ │ Music  │ │  SFX   │ │ Voice  │ │Ambient │                 │
│  │ │Bus (1) │ │Bus (2) │ │Bus (3) │ │Bus (4) │                 │
│  │ │        │ │[Comp]  │ │[HPF]   │ │[Reverb]│                 │
│  │ └────────┘ └────────┘ └────────┘ └────────┘                 │
│  │                │                                             │
│  │           ┌────┴────┐                                        │
│  │           │ ┌───────┴┐                                       │
│  │           │ │Weapons │                                       │
│  │           │ │Bus (5) │                                       │
│  │           │ │[Dist]  │                                       │
│  │           │ └────────┘                                       │
│  │           │                                                  │
└──┴───────────┴──────────────────────────────────────────────────┘
```

### 3.2 Creating Bus Layout in Editor

```
Editor → Bottom Panel → Audio

Bus Layout Features:
- Add/Remove buses
- Rename buses
- Add/remove effects
- Adjust volume (dB slider)
- Solo (S) button
- Mute (M) button
- Bypass (B) button
- Set send target

Save as: default_bus_layout.tres
```

### 3.3 Bus Operations in Code

```gdscript
# Creating and managing buses programmatically

class_name DynamicAudioBusManager
extends Node

func create_reverb_bus(bus_name: String, reverb_preset: String) -> int:
    # Add new bus
    AudioServer.add_bus(-1)  # -1 = at end
    var bus_idx = AudioServer.bus_count - 1

    # Set name
    AudioServer.set_bus_name(bus_idx, bus_name)

    # Route to master
    AudioServer.set_bus_send(bus_idx, "Master")

    # Add reverb effect
    var reverb = AudioEffectReverb.new()
    configure_reverb(reverb, reverb_preset)
    AudioServer.add_bus_effect(bus_idx, reverb)

    return bus_idx

func configure_reverb(reverb: AudioEffectReverb, preset: String):
    match preset:
        "small_room":
            reverb.room_size = 0.3
            reverb.damping = 0.5
            reverb.spread = 0.7
            reverb.wet = 0.3
            reverb.dry = 0.7
        "large_hall":
            reverb.room_size = 0.9
            reverb.damping = 0.2
            reverb.spread = 1.0
            reverb.wet = 0.5
            reverb.dry = 0.5
        "cave":
            reverb.room_size = 0.8
            reverb.damping = 0.1
            reverb.spread = 0.9
            reverb.wet = 0.6
            reverb.dry = 0.4

func fade_bus_volume(bus_name: String, target_db: float, duration: float):
    var bus_idx = AudioServer.get_bus_index(bus_name)
    var start_db = AudioServer.get_bus_volume_db(bus_idx)

    var tween = create_tween()
    tween.tween_method(
        func(db): AudioServer.set_bus_volume_db(bus_idx, db),
        start_db,
        target_db,
        duration
    )
```

### 3.4 Bus Effect Chain

```gdscript
# Setting up a complete bus effect chain

func setup_master_bus():
    var master_idx = 0  # Master is always index 0

    # Clear existing effects
    while AudioServer.get_bus_effect_count(master_idx) > 0:
        AudioServer.remove_bus_effect(master_idx, 0)

    # Add EQ (cut lows and highs for speakers)
    var eq = AudioEffectEQ10.new()
    eq.set_band_gain_db(0, -6.0)   # 31 Hz - cut
    eq.set_band_gain_db(1, -3.0)   # 62 Hz - reduce
    eq.set_band_gain_db(9, -3.0)   # 16 kHz - reduce
    AudioServer.add_bus_effect(master_idx, eq)

    # Add compressor
    var comp = AudioEffectCompressor.new()
    comp.threshold = -12.0
    comp.ratio = 4.0
    comp.attack_us = 10000.0  # 10ms
    comp.release_ms = 100.0
    comp.gain = 3.0
    AudioServer.add_bus_effect(master_idx, comp)

    # Add limiter (safety)
    var limiter = AudioEffectHardLimiter.new()
    limiter.ceiling_db = -0.3
    AudioServer.add_bus_effect(master_idx, limiter)
```

---

## 4. AudioStreamPlayer Nodes

### 4.1 AudioStreamPlayer (Non-Positional)

```gdscript
# AudioStreamPlayer - for UI, music, non-spatial audio

# Node properties:
# stream: AudioStream        - The audio to play
# volume_db: float          - Volume in decibels
# pitch_scale: float        - Pitch multiplier (1.0 = normal)
# playing: bool             - Read-only playing state
# autoplay: bool            - Start on ready
# stream_paused: bool       - Pause playback
# mix_target: MixTarget     - Stereo, Surround, or Center
# bus: StringName           - Target audio bus
# max_polyphony: int        - Max simultaneous plays (default 1)

# Common methods:
# play(from_position: float = 0.0)
# stop()
# seek(to_position: float)
# get_playback_position() -> float
# has_stream_playback() -> bool
# get_stream_playback() -> AudioStreamPlayback

# Signals:
# finished()               - Emitted when playback completes

# Example: Music player
class_name MusicPlayer
extends AudioStreamPlayer

@export var tracks: Array[AudioStream]
var current_track: int = 0

func _ready():
    finished.connect(_on_track_finished)
    bus = "Music"
    volume_db = -6.0

func play_track(index: int):
    current_track = index
    stream = tracks[current_track]
    play()

func _on_track_finished():
    current_track = (current_track + 1) % tracks.size()
    play_track(current_track)

func crossfade_to(new_stream: AudioStream, duration: float = 2.0):
    var tween = create_tween()

    # Fade out current
    tween.tween_property(self, "volume_db", -40.0, duration)
    tween.tween_callback(func():
        stream = new_stream
        play()
    )

    # Fade in new
    tween.tween_property(self, "volume_db", -6.0, duration)
```

### 4.2 AudioStreamPlayer2D

```gdscript
# AudioStreamPlayer2D - for 2D positional audio

# Additional properties (beyond AudioStreamPlayer):
# max_distance: float       - Maximum audible distance
# attenuation: float        - Volume falloff exponent
# max_polyphony: int        - Max simultaneous plays
# panning_strength: float   - Panning intensity (0-1)
# area_mask: int            - Which Area2D layers affect audio

# Example: 2D sound effect
class_name SoundEmitter2D
extends AudioStreamPlayer2D

@export var sounds: Array[AudioStream]
@export var pitch_variation: float = 0.1

func play_random():
    if sounds.is_empty():
        return

    stream = sounds[randi() % sounds.size()]
    pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
    play()

# Distance attenuation works with CanvasItem position
# Listener is the current Camera2D or viewport center
```

### 4.3 AudioStreamPlayer3D

```gdscript
# AudioStreamPlayer3D - for 3D positional audio

# 3D-specific properties:
# unit_size: float          - Distance for 0dB volume
# max_db: float             - Maximum volume
# attenuation_model: AttenuationModel
#   - ATTENUATION_INVERSE_DISTANCE
#   - ATTENUATION_INVERSE_SQUARE_DISTANCE
#   - ATTENUATION_LOGARITHMIC
#   - ATTENUATION_DISABLED

# Distance filtering:
# attenuation_filter_cutoff_hz: float  - Low-pass at distance (20500 = off)
# attenuation_filter_db: float         - Filter attenuation

# Doppler:
# doppler_tracking: DopplerTracking
#   - DOPPLER_TRACKING_DISABLED
#   - DOPPLER_TRACKING_IDLE_STEP
#   - DOPPLER_TRACKING_PHYSICS_STEP

# Directionality:
# emission_angle_enabled: bool
# emission_angle_degrees: float        - Cone angle
# emission_angle_filter_attenuation_db: float

# Area effects:
# area_mask: int                       - Which Area3D affect reverb/bus

# Example: 3D positional sound
class_name Sound3D
extends AudioStreamPlayer3D

func _ready():
    # Configure for realistic 3D audio
    attenuation_model = ATTENUATION_LOGARITHMIC
    unit_size = 10.0  # Full volume at 10 units
    max_db = 3.0

    # Enable distance filtering (muffled at distance)
    attenuation_filter_cutoff_hz = 5000.0
    attenuation_filter_db = -24.0

    # Enable doppler
    doppler_tracking = DOPPLER_TRACKING_PHYSICS_STEP

    # Directional emission (speaker cone)
    emission_angle_enabled = true
    emission_angle_degrees = 45.0
    emission_angle_filter_attenuation_db = -12.0

    bus = "SFX"

# 3D Audio requires AudioListener3D node
# Usually attached to Camera3D or player character
```

### 4.4 AudioListener3D

```gdscript
# AudioListener3D - the "ears" in 3D space

# Usually added as child of Camera3D
class_name PlayerAudioListener
extends AudioListener3D

func _ready():
    # Make this the active listener
    make_current()

func _process(_delta):
    # Listener position/rotation is automatic
    # based on node's global_transform
    pass

# Only one AudioListener3D can be current at a time
# If none is set, Camera3D position is used
```

---

## 5. Audio Stream Types

### 5.1 AudioStream Class Hierarchy

```
AudioStream (base)
├── AudioStreamWAV           # Uncompressed/IMA-ADPCM WAV
├── AudioStreamOggVorbis     # OGG Vorbis compressed
├── AudioStreamMP3           # MP3 compressed
├── AudioStreamGenerator     # Procedural/real-time
├── AudioStreamMicrophone    # Microphone input
├── AudioStreamPolyphonic    # Multiple voices
├── AudioStreamPlaylist      # Sequential playlist
├── AudioStreamRandomizer    # Random selection
└── AudioStreamSynchronized  # Synchronized playback
```

### 5.2 AudioStreamWAV

```gdscript
# AudioStreamWAV - uncompressed audio

# Properties:
# data: PackedByteArray     - Raw audio data
# format: Format            - FORMAT_8_BITS, FORMAT_16_BITS, FORMAT_IMA_ADPCM
# loop_mode: LoopMode       - LOOP_DISABLED, LOOP_FORWARD, LOOP_PING_PONG, LOOP_BACKWARD
# loop_begin: int           - Loop start sample
# loop_end: int             - Loop end sample
# mix_rate: int             - Sample rate
# stereo: bool              - Stereo or mono

# Best for: Short sound effects
# - Fast playback (no decoding)
# - Low CPU usage
# - Higher memory usage
```

### 5.3 AudioStreamOggVorbis

```gdscript
# AudioStreamOggVorbis - compressed streaming audio

# Properties:
# loop: bool                - Enable looping
# loop_offset: float        - Loop start time (seconds)
# bpm: float                - Beats per minute (for sync)
# beat_count: int           - Number of beats (for sync)
# bar_beats: int            - Beats per bar (for sync)

# Best for: Music, long ambient sounds
# - Small file size
# - Streaming (low memory)
# - Higher CPU usage

# Loading OGG at runtime:
func load_ogg_from_file(path: String) -> AudioStreamOggVorbis:
    var file = FileAccess.open(path, FileAccess.READ)
    var stream = AudioStreamOggVorbis.load_from_file(path)
    return stream
```

### 5.4 AudioStreamMP3

```gdscript
# AudioStreamMP3 - MP3 compressed audio

# Properties:
# loop: bool
# loop_offset: float
# bpm: float
# beat_count: int
# bar_beats: int

# Note: MP3 has slight decode delay
# Not recommended for precise timing or short SFX
```

### 5.5 AudioStreamRandomizer

```gdscript
# AudioStreamRandomizer - random stream selection

# Properties:
# random_pitch: float       - Pitch variation range
# random_volume_offset_db: float
# playback_mode: PlaybackMode
#   - PLAYBACK_RANDOM
#   - PLAYBACK_RANDOM_NO_REPEATS
#   - PLAYBACK_SEQUENTIAL
# streams_count: int        - Number of streams

# Example: Footstep variations
var footsteps = AudioStreamRandomizer.new()
footsteps.random_pitch = 0.1
footsteps.random_volume_offset_db = 3.0
footsteps.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS

# Add variations
footsteps.add_stream(0, preload("res://sfx/footstep_1.wav"))
footsteps.add_stream(1, preload("res://sfx/footstep_2.wav"))
footsteps.add_stream(2, preload("res://sfx/footstep_3.wav"))
```

### 5.6 AudioStreamPolyphonic

```gdscript
# AudioStreamPolyphonic - multiple simultaneous voices

# Properties:
# polyphony: int            - Maximum simultaneous voices

# Used with AudioStreamPlayer.max_polyphony
# Allows one player to handle multiple sounds

# Example: Rapid-fire weapon
var weapon_player: AudioStreamPlayer
var polyphonic_stream: AudioStreamPolyphonic

func _ready():
    polyphonic_stream = AudioStreamPolyphonic.new()
    polyphonic_stream.polyphony = 8

    weapon_player = AudioStreamPlayer.new()
    weapon_player.stream = polyphonic_stream
    weapon_player.bus = "Weapons"
    add_child(weapon_player)
    weapon_player.play()

func fire():
    var playback = weapon_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
    playback.play_stream(
        preload("res://sfx/gunshot.wav"),
        0.0,                    # Start position
        0.0,                    # Volume offset dB
        randf_range(0.9, 1.1)   # Pitch scale
    )
```

---

## 6. Audio Effects

### 6.1 Available Effects

```
AudioEffect (base)
├── AudioEffectAmplify           # Volume adjustment
├── AudioEffectBandLimitFilter   # Band-pass filter
├── AudioEffectBandPassFilter    # Band-pass filter
├── AudioEffectCapture           # Recording/analysis
├── AudioEffectChorus            # Chorus/ensemble
├── AudioEffectCompressor        # Dynamic range compression
├── AudioEffectDelay             # Echo/delay
├── AudioEffectDistortion        # Overdrive/distortion
├── AudioEffectEQ
│   ├── AudioEffectEQ6           # 6-band EQ
│   ├── AudioEffectEQ10          # 10-band EQ
│   └── AudioEffectEQ21          # 21-band EQ
├── AudioEffectFilter            # Base filter class
│   ├── AudioEffectLowPassFilter
│   ├── AudioEffectHighPassFilter
│   ├── AudioEffectLowShelfFilter
│   └── AudioEffectHighShelfFilter
├── AudioEffectHardLimiter       # Brick-wall limiter
├── AudioEffectLimiter           # Soft limiter (deprecated)
├── AudioEffectNotchFilter       # Notch/band-reject
├── AudioEffectPanner            # Stereo panning
├── AudioEffectPhaser            # Phaser effect
├── AudioEffectPitchShift        # Pitch shifting
├── AudioEffectRecord            # Recording to file
├── AudioEffectReverb            # Reverb
├── AudioEffectSpectrumAnalyzer  # FFT analysis
└── AudioEffectStereoEnhance     # Stereo widening
```

### 6.2 Filter Effects

```gdscript
# AudioEffectFilter and subclasses

# Base filter properties:
# cutoff_hz: float          # Cutoff frequency
# resonance: float          # Resonance (Q) - 0.1 to 5.0
# gain: float               # Gain for shelf filters
# db: FilterDB              # Filter slope (6, 12, 18, 24 dB/oct)

enum FilterDB {
    FILTER_6DB,
    FILTER_12DB,
    FILTER_18DB,
    FILTER_24DB
}

# Low-pass filter (removes highs)
var lpf = AudioEffectLowPassFilter.new()
lpf.cutoff_hz = 2000.0
lpf.resonance = 1.0
lpf.db = AudioEffectFilter.FILTER_24DB

# High-pass filter (removes lows)
var hpf = AudioEffectHighPassFilter.new()
hpf.cutoff_hz = 200.0
hpf.resonance = 0.5

# Band-pass filter (isolates band)
var bpf = AudioEffectBandPassFilter.new()
bpf.cutoff_hz = 1000.0
bpf.resonance = 2.0  # Narrower band

# Notch filter (removes frequency)
var notch = AudioEffectNotchFilter.new()
notch.cutoff_hz = 60.0  # Remove 60Hz hum
notch.resonance = 3.0   # Narrow notch
```

### 6.3 Dynamics Effects

```gdscript
# AudioEffectCompressor

var comp = AudioEffectCompressor.new()
comp.threshold = -20.0    # dB threshold
comp.ratio = 4.0          # Compression ratio
comp.attack_us = 20000.0  # Attack time (microseconds)
comp.release_ms = 250.0   # Release time (milliseconds)
comp.gain = 6.0           # Makeup gain (dB)
comp.mix = 1.0            # Wet/dry mix
comp.sidechain = "SFX"    # Sidechain bus name (optional)

# AudioEffectHardLimiter (brick-wall)

var limiter = AudioEffectHardLimiter.new()
limiter.ceiling_db = -0.3      # Output ceiling
limiter.pre_gain_db = 0.0      # Input gain
limiter.release = 0.1          # Release time (seconds)

# AudioEffectLimiter (deprecated - use HardLimiter)
```

### 6.4 Reverb & Delay

```gdscript
# AudioEffectReverb

var reverb = AudioEffectReverb.new()
reverb.room_size = 0.8    # Room size (0.0-1.0)
reverb.damping = 0.5      # High frequency damping
reverb.spread = 1.0       # Stereo spread
reverb.hipass = 0.0       # High-pass filter
reverb.wet = 0.5          # Wet level
reverb.dry = 0.5          # Dry level
reverb.predelay_msec = 20.0
reverb.predelay_feedback = 0.0

# AudioEffectDelay

var delay = AudioEffectDelay.new()
delay.dry = 1.0           # Dry level

# Tap 1
delay.tap1_active = true
delay.tap1_delay_ms = 250.0
delay.tap1_level_db = -6.0
delay.tap1_pan = -0.5     # Pan left

# Tap 2
delay.tap2_active = true
delay.tap2_delay_ms = 500.0
delay.tap2_level_db = -12.0
delay.tap2_pan = 0.5      # Pan right

# Feedback
delay.feedback_active = true
delay.feedback_delay_ms = 333.0
delay.feedback_level_db = -3.0
delay.feedback_lowpass = 4000.0
```

### 6.5 Modulation Effects

```gdscript
# AudioEffectChorus

var chorus = AudioEffectChorus.new()
chorus.dry = 0.5
chorus.wet = 0.5

# Voice 1
chorus.voice_count = 2
chorus.voice_1_delay_ms = 15.0
chorus.voice_1_rate_hz = 0.8
chorus.voice_1_depth_ms = 2.0
chorus.voice_1_level_db = 0.0
chorus.voice_1_cutoff_hz = 8000.0
chorus.voice_1_pan = -0.5

# Voice 2
chorus.voice_2_delay_ms = 20.0
chorus.voice_2_rate_hz = 1.2
chorus.voice_2_depth_ms = 3.0
chorus.voice_2_pan = 0.5

# AudioEffectPhaser

var phaser = AudioEffectPhaser.new()
phaser.range_min_hz = 440.0
phaser.range_max_hz = 1600.0
phaser.rate_hz = 0.5
phaser.feedback = 0.7
phaser.depth = 1.0
```

### 6.6 Analysis Effects

```gdscript
# AudioEffectSpectrumAnalyzer

var spectrum = AudioEffectSpectrumAnalyzer.new()
spectrum.buffer_length = 2.0    # Seconds of buffer
spectrum.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
spectrum.tap_back_pos = 0.0     # Analysis position in buffer

# Add to bus
AudioServer.add_bus_effect(bus_idx, spectrum)

# Get spectrum data in _process()
func _process(_delta):
    var spectrum_instance = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)
    if spectrum_instance is AudioEffectSpectrumAnalyzerInstance:
        var magnitude = spectrum_instance.get_magnitude_for_frequency_range(
            20.0, 200.0  # Low frequency range
        )
        print("Low freq magnitude: ", magnitude.length())

# AudioEffectCapture - for recording/real-time analysis

var capture = AudioEffectCapture.new()
capture.buffer_length = 0.1  # 100ms buffer

# Get buffer data
func get_audio_data():
    var capture_instance = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)
    if capture_instance is AudioEffectCaptureInstance:
        var frames = capture_instance.get_frames_available()
        var buffer = capture_instance.get_buffer(frames)
        # buffer is PackedVector2Array (stereo samples)
```

---

## 7. 3D Audio & Spatialization

### 7.1 Attenuation Models

```gdscript
# AudioStreamPlayer3D attenuation models

enum AttenuationModel {
    ATTENUATION_INVERSE_DISTANCE,        # 1/distance
    ATTENUATION_INVERSE_SQUARE_DISTANCE, # 1/distance²
    ATTENUATION_LOGARITHMIC,             # Log falloff
    ATTENUATION_DISABLED                 # No distance attenuation
}

# Calculation formulas:
# INVERSE_DISTANCE:
#   volume = unit_size / distance

# INVERSE_SQUARE_DISTANCE:
#   volume = (unit_size / distance)²

# LOGARITHMIC:
#   volume = -20 * log10(distance / unit_size)

# Practical setup:
func configure_3d_audio():
    var player = AudioStreamPlayer3D.new()

    # Realistic outdoor falloff
    player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
    player.unit_size = 10.0  # Full volume at 10 units

    # Indoor/controlled falloff
    player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
    player.unit_size = 5.0

    # Maximum volume cap
    player.max_db = 3.0  # +3dB max
```

### 7.2 Doppler Effect

```gdscript
# Doppler tracking configuration

enum DopplerTracking {
    DOPPLER_TRACKING_DISABLED,     # No doppler
    DOPPLER_TRACKING_IDLE_STEP,    # Update in _process
    DOPPLER_TRACKING_PHYSICS_STEP  # Update in _physics_process
}

# Enable doppler on camera
func setup_doppler():
    var camera = get_viewport().get_camera_3d()
    camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP

    # Enable on sound source
    var sound = $AudioStreamPlayer3D
    sound.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP

# Doppler pitch change:
# frequency_shift = c / (c + v_relative)
# where c = speed of sound, v_relative = relative velocity
```

### 7.3 Distance Filtering

```gdscript
# Low-pass filter for distant sounds (realism)

func setup_distance_filtering():
    var player = $AudioStreamPlayer3D

    # Enable distance-based low-pass
    player.attenuation_filter_cutoff_hz = 5000.0  # Start filtering at 5kHz
    player.attenuation_filter_db = -24.0          # Full attenuation at max distance

    # To disable:
    # player.attenuation_filter_cutoff_hz = 20500.0
```

### 7.4 Directional Audio

```gdscript
# Emission angle (speaker cone)

func setup_directional_sound():
    var speaker = $AudioStreamPlayer3D

    # Enable directional emission
    speaker.emission_angle_enabled = true
    speaker.emission_angle_degrees = 45.0                    # Half-cone angle
    speaker.emission_angle_filter_attenuation_db = -24.0     # Attenuation outside cone

    # This creates a sound "cone":
    # - Full volume in front (within cone)
    # - Attenuated/filtered behind/sides
```

---

## 8. Area-Based Audio

### 8.1 Audio Reverb Zones

```gdscript
# Area3D can affect audio within its volume

# In the Area3D inspector:
# - Audio Bus Override: Set bus for sounds inside
# - Reverb Bus: Set reverb send target
# - Reverb Amount: Reverb send level (0-1)
# - Reverb Uniformity: Blend reverb with position

# Example: Cave reverb zone
class_name ReverbZone
extends Area3D

@export var reverb_bus: String = "CaveReverb"
@export var reverb_amount: float = 0.8

func _ready():
    reverb_bus_enabled = true
    reverb_bus_name = reverb_bus
    reverb_bus_amount = reverb_amount
    reverb_bus_uniformity = 0.0  # Reverb varies with position
```

### 8.2 Audio Bus Overrides

```gdscript
# Area3D can redirect audio to different buses

class_name UnderwaterZone
extends Area3D

@export var underwater_bus: String = "Underwater"

func _ready():
    # Enable audio bus override
    audio_bus_override = true
    audio_bus_name = underwater_bus

    # Connect signals for additional effects
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)

func _on_body_entered(body):
    if body.is_in_group("player"):
        # Additional underwater effects
        apply_underwater_effect()

func _on_body_exited(body):
    if body.is_in_group("player"):
        remove_underwater_effect()
```

### 8.3 Area Mask System

```gdscript
# AudioStreamPlayer3D.area_mask controls which areas affect it

# Area layers (32 available)
# Layer 1: Reverb zones
# Layer 2: Acoustic environments
# Layer 3: Bus overrides

func setup_audio_area_masks():
    # Sound affected by reverb zones only
    var sfx = $AudioStreamPlayer3D
    sfx.area_mask = 1  # Only layer 1

    # Sound affected by all areas
    var ambient = $AmbientSound
    ambient.area_mask = 0xFFFFFFFF  # All layers

    # Sound not affected by any areas
    var ui_sound = $UISound
    ui_sound.area_mask = 0  # No layers
```

---

## 9. Procedural Audio

### 9.1 AudioStreamGenerator

```gdscript
# AudioStreamGenerator for real-time audio synthesis

class_name ProceduralSynth
extends AudioStreamPlayer

var playback: AudioStreamGeneratorPlayback
var sample_rate: float
var phase: float = 0.0

func _ready():
    # Create generator stream
    var generator = AudioStreamGenerator.new()
    generator.mix_rate = 44100.0
    generator.buffer_length = 0.1  # 100ms buffer

    stream = generator
    sample_rate = generator.mix_rate

    play()
    playback = get_stream_playback()

func _process(_delta):
    fill_buffer()

func fill_buffer():
    # Get number of frames to fill
    var frames_available = playback.get_frames_available()

    for i in range(frames_available):
        # Generate sine wave
        var sample = sin(phase * TAU)

        # Write stereo frame
        playback.push_frame(Vector2(sample, sample))

        # Advance phase
        phase += 440.0 / sample_rate  # 440 Hz
        if phase >= 1.0:
            phase -= 1.0
```

### 9.2 Advanced Synthesis

```gdscript
# More complex synthesis example

class_name SynthEngine
extends AudioStreamPlayer

var playback: AudioStreamGeneratorPlayback
var sample_rate: float

# Oscillators
var osc1_phase: float = 0.0
var osc2_phase: float = 0.0
var lfo_phase: float = 0.0

# Parameters
var osc1_freq: float = 440.0
var osc2_freq: float = 442.0  # Slight detune
var lfo_freq: float = 5.0
var lfo_amount: float = 0.5

# Envelope
var envelope: float = 0.0
var attack: float = 0.01
var release: float = 0.3
var note_on: bool = false

func _ready():
    var generator = AudioStreamGenerator.new()
    generator.mix_rate = 44100.0
    generator.buffer_length = 0.05
    stream = generator
    sample_rate = generator.mix_rate
    play()
    playback = get_stream_playback()

func _process(delta):
    update_envelope(delta)
    fill_buffer()

func update_envelope(delta):
    if note_on:
        envelope = move_toward(envelope, 1.0, delta / attack)
    else:
        envelope = move_toward(envelope, 0.0, delta / release)

func fill_buffer():
    var frames = playback.get_frames_available()

    for i in range(frames):
        # LFO modulation
        var lfo = sin(lfo_phase * TAU) * lfo_amount
        lfo_phase += lfo_freq / sample_rate
        if lfo_phase >= 1.0:
            lfo_phase -= 1.0

        # Oscillator 1 (saw wave)
        var osc1 = (osc1_phase * 2.0 - 1.0)
        osc1_phase += (osc1_freq * (1.0 + lfo)) / sample_rate
        if osc1_phase >= 1.0:
            osc1_phase -= 1.0

        # Oscillator 2 (saw wave, detuned)
        var osc2 = (osc2_phase * 2.0 - 1.0)
        osc2_phase += (osc2_freq * (1.0 + lfo)) / sample_rate
        if osc2_phase >= 1.0:
            osc2_phase -= 1.0

        # Mix and apply envelope
        var sample = (osc1 + osc2) * 0.5 * envelope * 0.5

        playback.push_frame(Vector2(sample, sample))

func play_note(freq: float):
    osc1_freq = freq
    osc2_freq = freq * 1.005  # Slight detune
    note_on = true

func stop_note():
    note_on = false
```

### 9.3 Real-Time Audio Analysis

```gdscript
# Analyzing audio in real-time

class_name AudioAnalyzer
extends Node

var spectrum_effect: AudioEffectSpectrumAnalyzer
var spectrum_instance: AudioEffectSpectrumAnalyzerInstance

func _ready():
    # Add spectrum analyzer to bus
    spectrum_effect = AudioEffectSpectrumAnalyzer.new()
    spectrum_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048

    var bus_idx = AudioServer.get_bus_index("Master")
    AudioServer.add_bus_effect(bus_idx, spectrum_effect)

    spectrum_instance = AudioServer.get_bus_effect_instance(bus_idx,
        AudioServer.get_bus_effect_count(bus_idx) - 1)

func get_frequency_magnitude(freq_low: float, freq_high: float) -> float:
    var mag = spectrum_instance.get_magnitude_for_frequency_range(
        freq_low, freq_high)
    # mag is Vector2 (left, right channels)
    return (mag.x + mag.y) / 2.0

func _process(_delta):
    # Example: Get bass energy
    var bass = get_frequency_magnitude(20, 200)
    var mids = get_frequency_magnitude(200, 2000)
    var highs = get_frequency_magnitude(2000, 20000)

    # Use for visualizations, etc.
```

---

## 10. Audio Import Settings

### 10.1 Import Options

```
Import Settings (in Godot Editor):

WAV Files:
- Force/8 Bit: Force 8-bit conversion
- Force/Mono: Force mono conversion
- Force/Max Rate: Maximum sample rate
- Force/Max Rate Hz: Rate if Max Rate enabled
- Edit/Trim: Remove silence from start/end
- Edit/Normalize: Normalize volume
- Edit/Loop Mode: Forward, Ping-Pong, Backward
- Compress/Mode: Disabled, RAM (IMA-ADPCM)

OGG Vorbis Files:
- Loop: Enable looping
- Loop Offset: Loop start time
- BPM: Beats per minute
- Beat Count: Number of beats
- Bar Beats: Beats per bar

MP3 Files:
- Loop: Enable looping
- Loop Offset: Loop start time
- BPM: Beats per minute
- Beat Count: Number of beats
- Bar Beats: Beats per bar
```

### 10.2 Format Recommendations

```
FORMAT SELECTION GUIDE:

SHORT SOUND EFFECTS (< 2 seconds):
- Format: WAV
- Compression: None (PCM) or IMA-ADPCM
- Force Mono: Yes (if not stereo effect)
- Sample Rate: Original or 22050
WHY: Fast playback, low CPU, acceptable memory

MEDIUM SOUND EFFECTS (2-10 seconds):
- Format: WAV with IMA-ADPCM
- Force Mono: If appropriate
WHY: Reduced memory, still fast

LONG AMBIENT SOUNDS:
- Format: OGG Vorbis
- Loop: Yes
- Quality: 5-7
WHY: Small file size, streaming

MUSIC:
- Format: OGG Vorbis
- Loop: Yes
- Quality: 6-8
- BPM/Beat Count: Set for synchronization
WHY: Excellent compression, streaming

VOICE/DIALOGUE:
- Format: OGG Vorbis
- Force Mono: Yes
- Quality: 4-6
WHY: Speech tolerates lower quality
```

---

## 11. Performance & Optimization

### 11.1 Voice Limits

```gdscript
# Godot manages voices automatically
# But you should limit polyphony

# Per-player polyphony
var player = AudioStreamPlayer.new()
player.max_polyphony = 4  # Max 4 overlapping sounds

# Global voice management
# Godot doesn't expose hard voice limits
# But excessive sounds WILL cause issues

# Best practices:
# 1. Set appropriate max_polyphony
# 2. Use AudioStreamRandomizer for variations
# 3. Stop sounds when offscreen/distant
# 4. Use bus-level processing, not per-source
```

### 11.2 Memory Optimization

```gdscript
# Memory usage by format:
# WAV (PCM): ~10 MB per minute (stereo, 44.1kHz, 16-bit)
# WAV (IMA-ADPCM): ~2.5 MB per minute
# OGG: ~0.5-1 MB per minute

# Optimization strategies:

# 1. Use appropriate format
# - Short SFX: WAV
# - Long audio: OGG

# 2. Reduce sample rate for non-critical sounds
# - Footsteps: 22050 Hz is often sufficient
# - Ambient: 22050-32000 Hz

# 3. Force mono for non-spatial sounds
# - Cuts memory in half

# 4. Use streaming for music
# - OGG streams from disk, minimal memory
```

### 11.3 CPU Optimization

```gdscript
# CPU usage considerations:

# 1. OGG decoding uses CPU
# - Limit simultaneous OGG streams
# - Use WAV for rapid-fire sounds

# 2. Effects use CPU
# - Apply to buses, not individual sources
# - Disable unused effects

# 3. 3D calculations
# - Disable doppler if not needed
# - Use simpler attenuation models
# - Reduce area_mask complexity

# 4. Don't call get_output_latency() every frame
# - Cache the value
# - Update occasionally
```

---

## 12. GDScript Audio API

### 12.1 Complete AudioServer API

```gdscript
# Full AudioServer singleton reference

# === BUS MANAGEMENT ===
AudioServer.bus_count -> int
AudioServer.add_bus(at_position: int = -1)
AudioServer.remove_bus(index: int)
AudioServer.move_bus(index: int, to_index: int)
AudioServer.get_bus_name(bus_idx: int) -> String
AudioServer.set_bus_name(bus_idx: int, name: String)
AudioServer.get_bus_index(bus_name: String) -> int

# === BUS PROPERTIES ===
AudioServer.get_bus_volume_db(bus_idx: int) -> float
AudioServer.set_bus_volume_db(bus_idx: int, volume_db: float)
AudioServer.is_bus_mute(bus_idx: int) -> bool
AudioServer.set_bus_mute(bus_idx: int, enable: bool)
AudioServer.is_bus_solo(bus_idx: int) -> bool
AudioServer.set_bus_solo(bus_idx: int, enable: bool)
AudioServer.is_bus_bypassing_effects(bus_idx: int) -> bool
AudioServer.set_bus_bypass_effects(bus_idx: int, enable: bool)

# === BUS ROUTING ===
AudioServer.get_bus_send(bus_idx: int) -> String
AudioServer.set_bus_send(bus_idx: int, send: String)

# === BUS EFFECTS ===
AudioServer.get_bus_effect_count(bus_idx: int) -> int
AudioServer.get_bus_effect(bus_idx: int, effect_idx: int) -> AudioEffect
AudioServer.get_bus_effect_instance(bus_idx: int, effect_idx: int, channel: int = 0) -> AudioEffectInstance
AudioServer.add_bus_effect(bus_idx: int, effect: AudioEffect, at_position: int = -1)
AudioServer.remove_bus_effect(bus_idx: int, effect_idx: int)
AudioServer.swap_bus_effects(bus_idx: int, effect_idx: int, by_effect_idx: int)
AudioServer.is_bus_effect_enabled(bus_idx: int, effect_idx: int) -> bool
AudioServer.set_bus_effect_enabled(bus_idx: int, effect_idx: int, enabled: bool)

# === METERING ===
AudioServer.get_bus_peak_volume_left_db(bus_idx: int, channel: int) -> float
AudioServer.get_bus_peak_volume_right_db(bus_idx: int, channel: int) -> float

# === SYSTEM INFO ===
AudioServer.get_mix_rate() -> float
AudioServer.get_output_latency() -> float
AudioServer.get_speaker_mode() -> SpeakerMode
AudioServer.get_time_since_last_mix() -> float
AudioServer.get_time_to_next_mix() -> float

# === LAYOUT ===
AudioServer.set_bus_layout(bus_layout: AudioBusLayout)
AudioServer.generate_bus_layout() -> AudioBusLayout

# === PLAYBACK INFO ===
AudioServer.get_playback_position() -> float
AudioServer.is_playing() -> bool
AudioServer.lock()
AudioServer.unlock()
```

### 12.2 Audio Manager Pattern

```gdscript
# Recommended audio manager singleton

class_name AudioManager
extends Node

# Bus indices cache
var _bus_cache: Dictionary = {}

# Sound pools
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_3d: Array[AudioStreamPlayer3D] = []
const POOL_SIZE = 16

func _ready():
    # Cache bus indices
    for i in range(AudioServer.bus_count):
        var name = AudioServer.get_bus_name(i)
        _bus_cache[name] = i

    # Create sound pools
    for i in range(POOL_SIZE):
        var player = AudioStreamPlayer.new()
        player.bus = "SFX"
        add_child(player)
        _sfx_pool.append(player)

        var player_3d = AudioStreamPlayer3D.new()
        player_3d.bus = "SFX"
        add_child(player_3d)
        _sfx_pool_3d.append(player_3d)

func play_sound(stream: AudioStream, volume_db: float = 0.0):
    var player = _get_available_player(_sfx_pool)
    if player:
        player.stream = stream
        player.volume_db = volume_db
        player.play()

func play_sound_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0):
    var player = _get_available_player(_sfx_pool_3d)
    if player:
        player.stream = stream
        player.volume_db = volume_db
        player.global_position = position
        player.play()

func _get_available_player(pool: Array):
    for player in pool:
        if not player.playing:
            return player
    # All busy, steal oldest
    return pool[0]

func set_bus_volume(bus_name: String, volume_db: float):
    if _bus_cache.has(bus_name):
        AudioServer.set_bus_volume_db(_bus_cache[bus_name], volume_db)

func set_bus_mute(bus_name: String, mute: bool):
    if _bus_cache.has(bus_name):
        AudioServer.set_bus_mute(_bus_cache[bus_name], mute)
```

---

## 13. Advanced Techniques

### 13.1 Music Synchronization

```gdscript
# Synchronizing gameplay to music

class_name MusicSyncManager
extends Node

signal beat
signal bar

@export var bpm: float = 120.0
@export var beats_per_bar: int = 4

var music_player: AudioStreamPlayer
var time_begin: float
var time_delay: float

func _ready():
    music_player = $MusicPlayer
    time_begin = Time.get_ticks_usec()
    time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
    music_player.play()

func get_current_beat() -> float:
    var time = (Time.get_ticks_usec() - time_begin) / 1000000.0
    time -= time_delay
    var beat = time * bpm / 60.0
    return beat

func _process(_delta):
    var beat = get_current_beat()
    var beat_int = int(beat)

    # Check for new beat
    if beat_int > _last_beat:
        _last_beat = beat_int
        emit_signal("beat")

        # Check for new bar
        if beat_int % beats_per_bar == 0:
            emit_signal("bar")

var _last_beat: int = -1
```

### 13.2 Ducking System

```gdscript
# Audio ducking (lower music when voice plays)

class_name DuckingManager
extends Node

var music_bus_idx: int
var original_volume: float
var is_ducked: bool = false

@export var duck_amount_db: float = -10.0
@export var duck_time: float = 0.3

func _ready():
    music_bus_idx = AudioServer.get_bus_index("Music")
    original_volume = AudioServer.get_bus_volume_db(music_bus_idx)

func duck():
    if not is_ducked:
        is_ducked = true
        var tween = create_tween()
        tween.tween_method(
            func(db): AudioServer.set_bus_volume_db(music_bus_idx, db),
            original_volume,
            original_volume + duck_amount_db,
            duck_time
        )

func unduck():
    if is_ducked:
        is_ducked = false
        var tween = create_tween()
        tween.tween_method(
            func(db): AudioServer.set_bus_volume_db(music_bus_idx, db),
            AudioServer.get_bus_volume_db(music_bus_idx),
            original_volume,
            duck_time
        )
```

### 13.3 Adaptive Audio

```gdscript
# Adaptive music layers

class_name AdaptiveMusicSystem
extends Node

var layers: Array[AudioStreamPlayer] = []
var target_volumes: Array[float] = []
var current_intensity: float = 0.0

func _ready():
    # Create layers
    for i in range(4):  # 4 intensity layers
        var player = AudioStreamPlayer.new()
        player.bus = "Music"
        player.volume_db = -80.0  # Start silent
        add_child(player)
        layers.append(player)
        target_volumes.append(-80.0)

func load_track(track_paths: Array[String]):
    for i in range(min(track_paths.size(), layers.size())):
        layers[i].stream = load(track_paths[i])

func start():
    # Start all layers synchronized
    var start_time = AudioServer.get_time_to_next_mix()
    for player in layers:
        player.play()

func set_intensity(value: float):
    # value: 0.0 = calm, 1.0 = intense
    current_intensity = clamp(value, 0.0, 1.0)

    # Calculate layer volumes
    for i in range(layers.size()):
        var layer_threshold = float(i) / layers.size()
        if current_intensity > layer_threshold:
            var layer_amount = (current_intensity - layer_threshold) / (1.0 / layers.size())
            target_volumes[i] = linear_to_db(clamp(layer_amount, 0.0, 1.0))
        else:
            target_volumes[i] = -80.0

func _process(delta):
    # Smoothly interpolate volumes
    for i in range(layers.size()):
        var current = layers[i].volume_db
        var target = target_volumes[i]
        layers[i].volume_db = move_toward(current, target, delta * 20.0)
```

---

## 14. Limitations & Proposals

### 14.1 Current Limitations

```
GODOT AUDIO LIMITATIONS:

1. Inflexible Routing
   - Series routing via buses only
   - No parallel/sidechain without workarounds
   - Limited compared to middleware

2. No Built-in HRTF
   - Basic 3D panning only
   - No binaural/HRTF by default
   - Requires external solutions

3. AudioStreamGenerator Issues
   - Reported problems at high sample rates
   - Limited real-time DSP capabilities
   - No node-based synthesis

4. No Middleware Integration
   - No official Wwise/FMOD support
   - Community plugins exist but limited

5. Limited Analysis Tools
   - Basic spectrum analyzer
   - No built-in oscilloscope
   - Limited profiling

6. Voice Management
   - No explicit voice limits
   - No virtualization system
   - No priority-based stealing
```

### 14.2 Proposed Improvements

```
COMMUNITY PROPOSALS (godot-proposals):

1. Audio Graph System
   - Similar to AnimationTree
   - Node-based audio routing
   - Modular synthesis support

2. Enhanced DSP
   - More effect types
   - Custom effect plugins
   - Real-time parameter modulation

3. HRTF Support
   - Native binaural audio
   - Custom HRTF loading

4. Improved Procedural Audio
   - Stable AudioStreamGenerator
   - Built-in oscillators
   - DSP nodes

5. Middleware Integration
   - Official Wwise plugin
   - FMOD support
```

---

## 15. Comparison with Other Engines

### 15.1 Godot vs Unity

| Feature | Godot | Unity |
|---------|-------|-------|
| **Built-in system** | Complete | Complete |
| **Bus/mixer** | Excellent | AudioMixer |
| **3D audio** | Good | Good (plugins) |
| **Effects** | Good | Good |
| **Procedural** | Basic | OnAudioFilterRead |
| **Middleware** | Limited | Excellent |
| **HRTF** | None | Plugin-based |
| **Cost** | Free (MIT) | Free/Paid |

### 15.2 Godot vs Unreal

| Feature | Godot | Unreal |
|---------|-------|--------|
| **Built-in system** | Good | Excellent |
| **Procedural** | Basic | MetaSounds |
| **Bus system** | Good | Submix |
| **3D audio** | Good | Excellent |
| **Complexity** | Simple | Complex |
| **Learning curve** | Low | High |

---

## 16. FluxForge Integration Points

### 16.1 Applicable Concepts

| Godot Concept | FluxForge Application |
|---------------|----------------------|
| **Bus system** | Routing architecture |
| **Effect chain** | DSP effect ordering |
| **Area-based audio** | Environment zones |
| **AudioStreamGenerator** | Real-time synthesis |
| **Spectrum analyzer** | Visualization |

### 16.2 Technical Insights

```rust
// Key lessons from Godot for FluxForge:

// 1. Simple but capable bus system
pub struct AudioBus {
    name: String,
    volume_db: f32,
    mute: bool,
    solo: bool,
    bypass_effects: bool,
    effects: Vec<Box<dyn AudioEffect>>,
    send: Option<BusId>,
}

// 2. Effect chain processing
impl AudioBus {
    pub fn process(&mut self, buffer: &mut AudioBuffer) {
        if self.bypass_effects {
            return;
        }

        for effect in &mut self.effects {
            effect.process(buffer);
        }
    }
}

// 3. Area-based audio zones
pub struct AudioArea {
    shape: AreaShape,
    reverb_bus: Option<BusId>,
    reverb_amount: f32,
    bus_override: Option<BusId>,
}

// 4. Simple 3D attenuation
pub fn calculate_attenuation(
    distance: f32,
    unit_size: f32,
    model: AttenuationModel
) -> f32 {
    match model {
        AttenuationModel::InverseDistance =>
            (unit_size / distance).min(1.0),
        AttenuationModel::InverseSquareDistance =>
            (unit_size / distance).powi(2).min(1.0),
        AttenuationModel::Logarithmic =>
            (-20.0 * (distance / unit_size).log10()).clamp(-80.0, 0.0),
        AttenuationModel::Disabled => 1.0,
    }
}
```

### 16.3 Key Takeaways

1. **Simplicity is valuable** — Godot proves capable audio doesn't need complexity
2. **Bus-based routing** — DAW-style approach is intuitive and powerful
3. **Built-in effects** — Core effects should be included, not external
4. **Open source benefit** — Full code access enables understanding
5. **Area-based audio** — Simple but effective for game environments
6. **Procedural potential** — AudioStreamGenerator concept is worth improving
7. **Community feedback** — Active proposals show where gaps exist

---

## Appendix A: Effect Reference

```
EFFECT PARAMETERS QUICK REFERENCE:

AudioEffectCompressor:
- threshold: -60 to 0 dB
- ratio: 1 to 48
- attack_us: 20 to 2000
- release_ms: 20 to 2000
- gain: -20 to 20 dB
- mix: 0 to 1 (parallel)
- sidechain: bus name

AudioEffectReverb:
- room_size: 0 to 1
- damping: 0 to 1
- spread: 0 to 1
- wet: 0 to 1
- dry: 0 to 1
- predelay_msec: 0 to 500
- predelay_feedback: 0 to 1
- hipass: 0 to 1

AudioEffectDelay:
- dry: 0 to 1
- tap[1-2]_active: bool
- tap[1-2]_delay_ms: 0 to 1500
- tap[1-2]_level_db: -60 to 0
- tap[1-2]_pan: -1 to 1
- feedback_active: bool
- feedback_delay_ms: 0 to 1500
- feedback_level_db: -60 to 0
- feedback_lowpass: 0 to 20000

AudioEffectFilter:
- cutoff_hz: 10 to 20000
- resonance: 0.1 to 5
- gain: 0 to 4 (shelf only)
- db: 6/12/18/24 dB slope

AudioEffectEQ:
- [band]_gain_db: -60 to 24
- Bands: 6, 10, or 21
```

---

## Appendix B: References

- [Godot Audio Documentation](https://docs.godotengine.org/en/stable/tutorials/audio/index.html)
- [AudioServer API](https://docs.godotengine.org/en/stable/classes/class_audioserver.html)
- [Audio Effects Tutorial](https://docs.godotengine.org/en/stable/tutorials/audio/audio_effects.html)
- [Audio Buses Guide](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html)
- [Godot Proposals - Audio](https://github.com/godotengine/godot-proposals/discussions/5704)

---

*Analysis complete. Document serves as reference for FluxForge audio engine development.*
