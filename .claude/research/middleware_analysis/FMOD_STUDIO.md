# FMOD Studio — Comprehensive Technical Analysis

**Version Analyzed:** FMOD 2.02.32
**Analysis Date:** January 2026
**Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## 1. EXECUTIVE SUMMARY

FMOD is Firelight Technologies' flagship audio middleware solution, representing one of the two dominant industry standards alongside Wwise. Used in thousands of games including Celeste, Hades, Hollow Knight, and many AAA titles. Known for its intuitive workflow and robust DSP architecture.

### Key Differentiators
- **Digital Audio Workstation UI** — Familiar interface for audio professionals
- **Flexible DSP Graph** — Programmable soft-synth architecture
- **Real/Virtual Voice System** — Efficient voice management
- **FSB Format** — Optimized streaming and memory-pointed loading
- **Free Indie License** — Accessible for small developers

---

## 2. ARCHITECTURE OVERVIEW

### 2.1 Two-API Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FMOD ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │                    FMOD STUDIO API (High-Level)                    ││
│  │                                                                    ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               ││
│  │  │ Events      │  │ Buses       │  │ Snapshots   │               ││
│  │  │ (Instances) │  │ (Mixing)    │  │ (States)    │               ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘               ││
│  │                                                                    ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               ││
│  │  │ Parameters  │  │ Banks       │  │ Live Update │               ││
│  │  │ (RTPC)      │  │ (Loading)   │  │ (Debug)     │               ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘               ││
│  │                                                                    ││
│  └────────────────────────────────────────────────────────────────────┘│
│                              │                                          │
│                              ▼                                          │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │                    FMOD CORE API (Low-Level)                       ││
│  │                                                                    ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               ││
│  │  │ System      │  │ Sound       │  │ Channel     │               ││
│  │  │ (Init/Mix)  │  │ (Assets)    │  │ (Voices)    │               ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘               ││
│  │                                                                    ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               ││
│  │  │ ChannelGroup│  │ DSP         │  │ Geometry    │               ││
│  │  │ (Submix)    │  │ (Effects)   │  │ (Occlusion) │               ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘               ││
│  │                                                                    ││
│  └────────────────────────────────────────────────────────────────────┘│
│                              │                                          │
│                              ▼                                          │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │                    PLATFORM OUTPUT LAYER                           ││
│  │                                                                    ││
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     ││
│  │  │ Windows │ │ PS5     │ │ Xbox    │ │ Switch  │ │ Mobile  │     ││
│  │  │ WASAPI  │ │ Tempest │ │ XAudio2 │ │ Native  │ │ AAudio  │     ││
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘     ││
│  │                                                                    ││
│  └────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Studio API vs Core API

```
┌─────────────────────────────────────────────────────────────────┐
│              API COMPARISON                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FMOD STUDIO API:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Works with FMOD Studio authoring tool                 │   │
│  │ • Event-based workflow                                   │   │
│  │ • Designer-driven sound design                           │   │
│  │ • Built-in mixing, routing, effects                     │   │
│  │ • Parameter-driven behaviors                             │   │
│  │ • Snapshots for mix states                               │   │
│  │ • Live Update for runtime editing                        │   │
│  │                                                         │   │
│  │ Use when: Designer/composer workflow, adaptive audio     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  FMOD CORE API:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Standalone low-level API                              │   │
│  │ • Direct sound loading and playback                     │   │
│  │ • Manual DSP chain management                           │   │
│  │ • Sample-accurate timing                                │   │
│  │ • Geometry-based occlusion                              │   │
│  │ • Custom codec plugins                                   │   │
│  │                                                         │   │
│  │ Use when: Procedural audio, custom engines, maximum     │   │
│  │           control, non-Studio projects                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  NOTE: Studio API internally uses Core API. You can access     │
│        Core API from Studio API for advanced features.         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Software Mixing Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                SOFTWARE MIXING                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FMOD uses 100% software mixing:                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • All voices software-mixed (no hardware voice reliance)│   │
│  │ • Consistent behavior across all platforms              │   │
│  │ • Advanced features impossible with hardware:           │   │
│  │   - Real-time DSP effects on all voices                │   │
│  │   - Sample-accurate timing                              │   │
│  │   - Dynamic voice routing                               │   │
│  │   - Virtual voice system                                │   │
│  │ • Optimized for multicore CPUs                          │   │
│  │ • Mobile platforms benefit from modern CPUs             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  BUFFER CONFIGURATION:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Default buffer size: Optimized per output type          │   │
│  │                                                         │   │
│  │ Guidelines:                                             │   │
│  │ • Don't make smaller (increases CPU, cache misses)      │   │
│  │ • Don't exceed 20ms (audible parameter lag)             │   │
│  │ • Let FMOD choose optimal size                          │   │
│  │                                                         │   │
│  │ Tradeoffs:                                              │   │
│  │ Smaller = Lower latency, Higher CPU                     │   │
│  │ Larger  = Higher latency, Lower CPU, parameter delay    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. DSP ARCHITECTURE

### 3.1 DSP Graph Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD DSP GRAPH                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    DSP NETWORK                           │   │
│  │                                                         │   │
│  │  Nodes connected in a directed acyclic graph (DAG)      │   │
│  │  Each node = DSP unit with inputs/outputs               │   │
│  │                                                         │   │
│  │     ┌──────┐     ┌──────┐     ┌──────┐                 │   │
│  │     │Sound1│────▶│ EQ   │────▶│      │                 │   │
│  │     └──────┘     └──────┘     │      │                 │   │
│  │                               │Mixer │────▶ Output      │   │
│  │     ┌──────┐     ┌──────┐     │      │                 │   │
│  │     │Sound2│────▶│Reverb│────▶│      │                 │   │
│  │     └──────┘     └──────┘     └──────┘                 │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  DSP CHAIN (Channel/ChannelGroup):                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Index 0: Head (closest to output)                     │   │
│  │  ...                                                    │   │
│  │  Index N-2: Tail (closest to input)                    │   │
│  │  Index N-1: Fader (volume/pan control, always last)    │   │
│  │                                                         │   │
│  │  API:                                                   │   │
│  │  • addDSP(index, dsp)      - Insert at position        │   │
│  │  • removeDSP(dsp)          - Remove from chain         │   │
│  │  • getNumDSPs()            - Count DSPs in chain       │   │
│  │  • getDSP(index)           - Get DSP at position       │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Built-in DSP Effects

```
┌─────────────────────────────────────────────────────────────────┐
│               FMOD BUILT-IN DSP EFFECTS (30+)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DYNAMICS:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Compressor      - Dynamic range compression           │   │
│  │ • Limiter         - Peak limiting                       │   │
│  │ • Normalize       - Peak normalization                  │   │
│  │ • Envelope Follower - Amplitude detection              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  FILTERING:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Lowpass         - 12/24/48dB resonant                 │   │
│  │ • Highpass        - 12/24dB resonant                    │   │
│  │ • Multiband EQ    - Parametric equalizer                │   │
│  │ • Three EQ        - Simple 3-band EQ                    │   │
│  │ • IT Lowpass      - Impulse Tracker style               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SPATIAL:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Pan             - Stereo/Surround panning             │   │
│  │ • 3D Panner       - Distance-based spatialization       │   │
│  │ • Object Panner   - Object-based audio                  │   │
│  │ • Convolution Reverb - Impulse response reverb          │   │
│  │ • SFX Reverb      - Parametric I3DL2 reverb             │   │
│  │ • Channel Mix     - Matrix mixing                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  TIME-BASED:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Delay           - Mono/stereo delay                   │   │
│  │ • Echo            - Feedback delay                      │   │
│  │ • Flange          - Flanging effect                     │   │
│  │ • Chorus          - Chorus modulation                   │   │
│  │ • Tremolo         - Amplitude modulation                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PITCH/FREQUENCY:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Pitch Shift     - Time-domain pitch shifting          │   │
│  │ • FFT             - Frequency analysis                  │   │
│  │ • Oscillator      - Sine/square/saw/triangle/noise      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  UTILITY:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Fader           - Volume/pan (built into channels)    │   │
│  │ • Mixer           - Multi-input mixing                  │   │
│  │ • Transceiver     - Send/return routing                 │   │
│  │ • Return          - Receive from sends                  │   │
│  │ • Loudness Meter  - LUFS/dB metering                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Sample-Accurate Control

```
┌─────────────────────────────────────────────────────────────────┐
│              SAMPLE-ACCURATE TIMING                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DSP CLOCK SYSTEM:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Every Channel/ChannelGroup has a DSP clock              │   │
│  │ Clock = sample count since System::init()               │   │
│  │                                                         │   │
│  │ API:                                                    │   │
│  │ • getDSPClock() - Get current clock values              │   │
│  │ • setDelay()    - Set sample-accurate start/stop        │   │
│  │ • getDelay()    - Get scheduled start/stop              │   │
│  │ • addFadePoint()- Add sample-accurate fade point        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  FADE POINTS:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Volume                                                 │   │
│  │    1.0 ┤        ┌──────────────┐                       │   │
│  │        │       ╱                ╲                       │   │
│  │        │      ╱                  ╲                      │   │
│  │    0.0 ┤─────╱                    ╲─────────           │   │
│  │        └────┬─────┬─────────────┬──┬────────▶ Time     │   │
│  │           Start  Peak          Fade End                │   │
│  │          (sample-accurate timing)                       │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  USE CASES:                                                     │
│  • Seamless music crossfades                                    │
│  • Synchronized sound layers                                    │
│  • Beat-matched transitions                                     │
│  • Ducking with precise timing                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. VOICE MANAGEMENT

### 4.1 Real vs Virtual Voices

```
┌─────────────────────────────────────────────────────────────────┐
│                VOICE MANAGEMENT SYSTEM                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ VIRTUAL VOICES                                          │   │
│  │                                                         │   │
│  │ • FMOD tracks state without audio processing            │   │
│  │ • No CPU cost for decoding/DSP                         │   │
│  │ • Position tracking continues                           │   │
│  │ • Can become "real" when audible again                 │   │
│  │                                                         │   │
│  │ Typical setting: 512-1024 virtual voices               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ REAL VOICES                                             │   │
│  │                                                         │   │
│  │ • Full audio processing (decode, DSP, mix)             │   │
│  │ • Maximum CPU cost                                      │   │
│  │ • Limited by hardware/performance budget               │   │
│  │                                                         │   │
│  │ Typical setting: 32-64 real voices                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  VIRTUALIZATION BEHAVIOR:                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  When real voice limit reached:                        │   │
│  │  1. FMOD evaluates audibility of all voices            │   │
│  │  2. Quietest/least important voices → virtual          │   │
│  │  3. Freed real voice → new sound                       │   │
│  │                                                         │   │
│  │  Audibility factors:                                    │   │
│  │  • Volume (after all effects)                          │   │
│  │  • Distance attenuation                                │   │
│  │  • Priority setting                                     │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CONFIGURATION EXAMPLE:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ // FMOD_ADVANCEDSETTINGS                                │   │
│  │ maxRealVoices = 64;      // Audio processing limit     │   │
│  │ maxVirtualVoices = 1024; // Tracking limit             │   │
│  │                                                         │   │
│  │ Benefits:                                               │   │
│  │ • Thousands of potential sounds                        │   │
│  │ • Only audible subset uses CPU                         │   │
│  │ • Automatic management                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Channel and ChannelGroup Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│              MIXING HIERARCHY                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                    ┌──────────────────┐                         │
│                    │   Master Group   │                         │
│                    │   (System)       │                         │
│                    └────────┬─────────┘                         │
│                             │                                    │
│         ┌───────────────────┼───────────────────┐               │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Music     │    │    SFX      │    │   Voice     │         │
│  │   Group     │    │   Group     │    │   Group     │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
│         │                  │                  │                 │
│    ┌────┴────┐        ┌────┴────┐        ┌────┴────┐           │
│    │         │        │         │        │         │           │
│    ▼         ▼        ▼         ▼        ▼         ▼           │
│ ┌─────┐ ┌─────┐  ┌─────┐ ┌─────┐  ┌─────┐ ┌─────┐             │
│ │Ch 1 │ │Ch 2 │  │Ch 3 │ │Ch 4 │  │Ch 5 │ │Ch 6 │             │
│ └─────┘ └─────┘  └─────┘ └─────┘  └─────┘ └─────┘             │
│                                                                  │
│  API:                                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ System::createChannelGroup() - Create submix            │   │
│  │ ChannelGroup::addGroup()     - Parent to child          │   │
│  │ Channel::setChannelGroup()   - Assign to group          │   │
│  │ ChannelGroup::getDSP()       - Access group DSP chain   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. CODEC SYSTEM

### 5.1 Codec Comparison

```
┌─────────────────────────────────────────────────────────────────┐
│                   FMOD CODEC SUPPORT                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ PCM (WAV, AIFF)                                            ││
│  │                                                            ││
│  │ CPU Cost:     ★☆☆☆☆ (Lowest)                              ││
│  │ File Size:    ★★★★★ (Largest)                             ││
│  │ Quality:      ★★★★★ (Perfect)                             ││
│  │ Load Method:  FMOD_CREATESAMPLE (into memory)             ││
│  │                                                            ││
│  │ Use: Short critical sounds, low-latency requirements      ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ FADPCM (FMOD ADPCM)                                        ││
│  │                                                            ││
│  │ CPU Cost:     ★★☆☆☆ (Very Low)                            ││
│  │ File Size:    ★★★☆☆ (4:1 compression)                     ││
│  │ Quality:      ★★★★☆ (Very Good - no "hiss")               ││
│  │ Memory:       3,128 bytes per voice instance              ││
│  │ Default:      32 simultaneous ADPCM channels              ││
│  │                                                            ││
│  │ Advantages over standard ADPCM:                           ││
│  │ • No branching (faster on all CPUs)                       ││
│  │ • Superior quality                                        ││
│  │ • No characteristic "hiss"                                ││
│  │                                                            ││
│  │ Use: Mobile, ambiences, high-polyphony sounds            ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ VORBIS                                                     ││
│  │                                                            ││
│  │ CPU Cost:     ★★★☆☆ (Medium)                              ││
│  │ File Size:    ★★☆☆☆ (10:1 typical)                        ││
│  │ Quality:      ★★★★☆ (Very Good)                           ││
│  │ Memory:       23,256 bytes per voice instance             ││
│  │                                                            ││
│  │ FSB Optimization:                                          ││
│  │ • Strips 'Ogg' container, keeps 'Vorbis'                  ││
│  │ • Shared codebook across sounds (saves MB)                ││
│  │                                                            ││
│  │ Use: Music, voice-over, default for quality needs        ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ OPUS                                                       ││
│  │                                                            ││
│  │ CPU Cost:     ★★★★☆ (High)                                ││
│  │ File Size:    ★☆☆☆☆ (Best compression)                    ││
│  │ Quality:      ★★★★★ (Excellent)                           ││
│  │                                                            ││
│  │ Platform Support:                                          ││
│  │ • PS5: Hardware decode available                          ││
│  │ • Others: Software decode                                  ││
│  │                                                            ││
│  │ Use: Large music files, when hardware decode available   ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ MP3                                                        ││
│  │                                                            ││
│  │ CPU Cost:     ★★★☆☆ (Medium)                              ││
│  │ File Size:    ★★☆☆☆ (Good compression)                    ││
│  │ Quality:      ★★★☆☆ (Good)                                ││
│  │                                                            ││
│  │ Note: Vorbis generally preferred for games                ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  PLATFORM HARDWARE CODECS:                                      │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ PS5:    AT9 (dedicated hardware decode)                   ││
│  │ PS4:    AT9 (dedicated hardware decode)                   ││
│  │ Xbox:   XMA2 (hardware decode)                            ││
│  │ Switch: Hardware ADPCM, Opus (v10+)                       ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 FSB Format

```
┌─────────────────────────────────────────────────────────────────┐
│               FSB (FMOD SOUND BANK) FORMAT                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ADVANTAGES:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Optimized for game loading                            │   │
│  │ • Multiple sounds in single file                        │   │
│  │ • No-seek loading (3 contiguous reads):                 │   │
│  │   1. Main header                                        │   │
│  │   2. Sub-sound metadata                                 │   │
│  │   3. Raw audio data                                     │   │
│  │ • Memory-point feature (zero-copy load)                 │   │
│  │ • Vorbis codebook sharing                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  MEMORY-POINT LOADING:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Traditional:                                           │   │
│  │  [Disk] → [Load Buffer] → [FMOD Allocation] → [Use]    │   │
│  │                                                         │   │
│  │  Memory-Point:                                          │   │
│  │  [Disk] → [Your Memory] → [FMOD Points To It] → [Use]  │   │
│  │                                                         │   │
│  │  Benefits:                                              │   │
│  │  • No extra memory allocation                           │   │
│  │  • Use existing memory-mapped files                     │   │
│  │  • Faster load times                                    │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  LOADING MODES:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ FMOD_CREATESAMPLE                                       │   │
│  │ • Decompress and load entire sound into memory          │   │
│  │ • Lowest CPU, highest memory                            │   │
│  │ • Best for: Short, frequently played sounds             │   │
│  │                                                         │   │
│  │ FMOD_CREATECOMPRESSEDSAMPLE                             │   │
│  │ • Load compressed data into memory                      │   │
│  │ • Decode in realtime during playback                    │   │
│  │ • Balance of CPU and memory                             │   │
│  │ • Supports: MP3, Vorbis, FADPCM, AT9, XMA              │   │
│  │                                                         │   │
│  │ FMOD_CREATESTREAM                                       │   │
│  │ • Stream from disk during playback                      │   │
│  │ • Only small buffer in memory                           │   │
│  │ • Best for: Music, ambient loops, voice-over            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Async Loading

```
┌─────────────────────────────────────────────────────────────────┐
│                 ASYNC FILE LOADING                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FMOD_FILE_ASYNCREAD_CALLBACK:                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Enables deferred, prioritized loading                  │   │
│  │                                                         │   │
│  │  Flow:                                                  │   │
│  │  1. FMOD requests data via callback                     │   │
│  │  2. Return immediately (no data yet)                    │   │
│  │  3. Load data in background thread                      │   │
│  │  4. When ready, set 'done' flag in FMOD_ASYNCREADINFO   │   │
│  │  5. FMOD consumes data                                  │   │
│  │                                                         │   │
│  │  Use cases:                                             │   │
│  │  • Custom asset streaming systems                       │   │
│  │  • Priority-based loading queues                        │   │
│  │  • Platform-specific I/O optimization                   │   │
│  │                                                         │   │
│  │  Caution:                                               │   │
│  │  • Don't wait too long (streams will stutter)           │   │
│  │  • Increase stream buffer sizes if needed               │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. SPATIAL AUDIO

### 6.1 3D Audio System

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD 3D AUDIO                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  3D SOUND ATTRIBUTES:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Position      - XYZ world coordinates                   │   │
│  │ Velocity      - For Doppler effect                      │   │
│  │ Orientation   - Forward/up vectors (cone attenuation)   │   │
│  │ Min Distance  - Distance where attenuation starts       │   │
│  │ Max Distance  - Distance where attenuation ends         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  DISTANCE ATTENUATION CURVES:                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  FMOD_3D_INVERSEROLLOFF (Default):                     │   │
│  │  • Realistic inverse-distance falloff                   │   │
│  │  • mindistance / (distance - mindistance + mindistance)│   │
│  │                                                         │   │
│  │  FMOD_3D_LINEARROLLOFF:                                │   │
│  │  • Linear attenuation between min/max                  │   │
│  │  • Simpler, less realistic                             │   │
│  │                                                         │   │
│  │  FMOD_3D_LINEARSQUAREROLLOFF:                          │   │
│  │  • Linear squared (power curve)                        │   │
│  │                                                         │   │
│  │  FMOD_3D_CUSTOMROLLOFF:                                │   │
│  │  • User-defined curve points                           │   │
│  │  • Maximum flexibility                                  │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  MULTICHANNEL 3D:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Default: Multichannel → Mono point source               │   │
│  │                                                         │   │
│  │ set3DSpread():                                          │   │
│  │ • Spread channels around listener                       │   │
│  │ • Close sounds spread into multiple speakers            │   │
│  │ • Distant sounds collapse to point                      │   │
│  │ • Creates envelopment effect                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Occlusion and Geometry

```
┌─────────────────────────────────────────────────────────────────┐
│                GEOMETRY-BASED OCCLUSION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BASIC OCCLUSION (API-driven):                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Channel::set3DOcclusion(directOcclusion, reverbOcclusion)│   │
│  │                                                         │   │
│  │ • Values 0.0 (no occlusion) to 1.0 (full occlusion)    │   │
│  │ • Applies lowpass filtering                             │   │
│  │ • Simulates sounds through walls                        │   │
│  │ • Game calculates occlusion (raycasts, etc.)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  GEOMETRY ENGINE:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ System::createGeometry()                                │   │
│  │ Geometry::addPolygon()                                  │   │
│  │                                                         │   │
│  │ Features:                                               │   │
│  │ • Real-time polygon occlusion processing                │   │
│  │ • Obstruct dry signals                                  │   │
│  │ • Obstruct reverb signals                               │   │
│  │ • Exclude reverb from areas                             │   │
│  │                                                         │   │
│  │ Per-polygon properties:                                 │   │
│  │ • Direct occlusion factor                               │   │
│  │ • Reverb occlusion factor                               │   │
│  │ • Double-sided flag                                     │   │
│  │                                                         │   │
│  │ Transforms:                                             │   │
│  │ • setPosition() - Translate geometry                    │   │
│  │ • setRotation() - Rotate geometry                       │   │
│  │ • setScale()    - Scale geometry                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Reverb System

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD REVERB SYSTEM                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  REVERB TYPES:                                                  │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ SFX REVERB (Parametric)                                 │   │
│  │                                                         │   │
│  │ • I3DL2 compliant                                       │   │
│  │ • High quality                                          │   │
│  │ • Fast, configurable                                    │   │
│  │                                                         │   │
│  │ Parameters:                                             │   │
│  │ - DecayTime, Room, RoomHF                              │   │
│  │ - PreDelay, Diffusion, Density                         │   │
│  │ - LowShelfFreq, LowShelfGain                           │   │
│  │ - HighCut, EarlyLateMix                                │   │
│  │ - WetLevel, DryLevel                                    │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CONVOLUTION REVERB                                      │   │
│  │                                                         │   │
│  │ • Impulse response based                                │   │
│  │ • Realistic environments                                │   │
│  │ • Outdoor spaces (difficult with parametric)            │   │
│  │                                                         │   │
│  │ Platform support:                                       │   │
│  │ • PS5: ACM convolution (hardware accelerated)          │   │
│  │ • Xbox: XDSP convolution (hardware accelerated)         │   │
│  │ • All: Software convolution                             │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  3D REVERB ZONES:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Virtual system simulating many environments          │   │
│  │ • Uses only 1 physical reverb                          │   │
│  │ • Hundreds of zones possible                            │   │
│  │                                                         │   │
│  │ System::createReverb3D()                               │   │
│  │ Reverb3D::set3DAttributes(position, minDist, maxDist)  │   │
│  │ Reverb3D::setProperties(FMOD_REVERB_PROPERTIES)        │   │
│  │                                                         │   │
│  │ Features:                                               │   │
│  │ • Reverb panning based on zone position                │   │
│  │ • Reverb occlusion (doesn't go through walls)          │   │
│  │ • Blend between multiple zones                         │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 Third-Party Spatial Audio

```
┌─────────────────────────────────────────────────────────────────┐
│            THIRD-PARTY SPATIAL AUDIO PLUGINS                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STEAM AUDIO:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Physics-based sound propagation                       │   │
│  │ • HRTF spatialization                                   │   │
│  │ • Convolution reverb from geometry                      │   │
│  │ • Real-time diffraction                                 │   │
│  │ • Dynamic geometry support                              │   │
│  │ • Multiple propagation paths                            │   │
│  │                                                         │   │
│  │ Effects:                                                │   │
│  │ - Spatializer (HRTF)                                   │   │
│  │ - Reverb (geometry-based)                              │   │
│  │ - Mixer Return (propagation)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  META XR AUDIO SDK:                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Optimized for Quest/Rift                              │   │
│  │ • Proprietary HRTF                                      │   │
│  │ • Superior localization                                 │   │
│  │ • Low latency                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  RESONANCE AUDIO (Google):                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Ambisonics-based                                      │   │
│  │ • Open source                                           │   │
│  │ • Cross-platform                                        │   │
│  │ • Room acoustics                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PS5 TEMPEST 3D:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Sony Propagation Audio integration                   │   │
│  │ • Hardware accelerated HRTF                            │   │
│  │ • Object-based audio                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. FMOD STUDIO AUTHORING

### 7.1 Event System

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD STUDIO EVENTS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  EVENT STRUCTURE:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │                 EVENT                            │   │   │
│  │  │                                                  │   │   │
│  │  │  ┌─────────────────────────────────────────┐   │   │   │
│  │  │  │ TRACKS (parallel layers)                │   │   │   │
│  │  │  │                                         │   │   │   │
│  │  │  │  Track 1: Audio │ ▓▓▓▓░░░░▓▓▓▓▓       │   │   │   │
│  │  │  │  Track 2: Audio │ ░░▓▓▓▓▓░░░░░░       │   │   │   │
│  │  │  │  Track 3: Return│ (Reverb bus)         │   │   │   │
│  │  │  │                                         │   │   │   │
│  │  │  │  ───────────────▶ Timeline             │   │   │   │
│  │  │  │                                         │   │   │   │
│  │  │  └─────────────────────────────────────────┘   │   │   │
│  │  │                                                  │   │   │
│  │  │  ┌─────────────────────────────────────────┐   │   │   │
│  │  │  │ PARAMETER SHEETS (automation lanes)     │   │   │   │
│  │  │  │                                         │   │   │   │
│  │  │  │  Volume:    ▁▂▃▅▇█▇▅▃▂▁               │   │   │   │
│  │  │  │  Pitch:     ▅▅▅▅▇▇▇▅▅▅▅               │   │   │   │
│  │  │  │  Intensity: ▁▁▂▃▅▇██▇▅▃▂              │   │   │   │
│  │  │  │                                         │   │   │   │
│  │  │  └─────────────────────────────────────────┘   │   │   │
│  │  │                                                  │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  EVENT TYPES:                                                   │
│  • 2D Events      - Non-positional audio                       │
│  • 3D Events      - Spatial audio with attenuation             │
│  • Snapshot Events- Mix state changes                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Parameter System

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD PARAMETERS                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PARAMETER TYPES:                                               │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CONTINUOUS PARAMETER                                    │   │
│  │                                                         │   │
│  │ • Float value within range (e.g., 0-100)               │   │
│  │ • Smooth interpolation                                  │   │
│  │ • Automatable via curves                                │   │
│  │                                                         │   │
│  │ Examples: Health, Speed, Distance, Intensity           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ DISCRETE PARAMETER                                      │   │
│  │                                                         │   │
│  │ • Integer/labeled values                                │   │
│  │ • Snaps between states                                  │   │
│  │ • Like Wwise Switches                                   │   │
│  │                                                         │   │
│  │ Examples: Surface type, Weather, Area                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ LABELED PARAMETER                                       │   │
│  │                                                         │   │
│  │ • Named labels instead of numbers                       │   │
│  │ • Easier to understand in code                          │   │
│  │                                                         │   │
│  │ Examples: "Wood", "Metal", "Grass" for surface         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PARAMETER SCOPE:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ LOCAL:  Per-event instance                              │   │
│  │ GLOBAL: Shared across all events                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  BUILT-IN PARAMETERS:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Distance      - 3D distance from listener             │   │
│  │ • Direction     - Angle from listener                   │   │
│  │ • Elevation     - Vertical angle                        │   │
│  │ • Event Cone    - Cone angle for emitter               │   │
│  │ • Event Orientation - Emitter facing                    │   │
│  │ • Speed         - Emitter velocity                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.3 Snapshots

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD SNAPSHOTS                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PURPOSE:                                                       │
│  • Store and recall mix states                                  │
│  • Blend between different mixes                                │
│  • Context-sensitive audio mixing                               │
│                                                                  │
│  SNAPSHOT CAPABILITIES:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Bus volume overrides                                  │   │
│  │ • Bus effect parameter changes                          │   │
│  │ • VCA level changes                                     │   │
│  │ • Effect bypass states                                  │   │
│  │ • Transition time (fade duration)                       │   │
│  │                                                         │   │
│  │ CANNOT change:                                          │   │
│  │ • Event playback state                                  │   │
│  │ • Event parameters                                      │   │
│  │ • Routing structure                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  INTENSITY SYSTEM:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Intensity: 0% ─────────────────────── 100%            │   │
│  │                                                         │   │
│  │  0%:   No effect (normal mix)                          │   │
│  │  50%:  Halfway between normal and snapshot             │   │
│  │  100%: Full snapshot effect                            │   │
│  │                                                         │   │
│  │  Multiple snapshots blend additively                   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  USE CASES:                                                     │
│  • Pause menu (duck music, mute SFX)                           │
│  • Underwater (lowpass, reverb change)                          │
│  • Combat (boost action sounds)                                 │
│  • Stealth (quiet music, enhanced footsteps)                   │
│  • Slow motion (pitch shift, reverb)                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. ADAPTIVE MUSIC

### 8.1 Horizontal Adaptivity

```
┌─────────────────────────────────────────────────────────────────┐
│               HORIZONTAL RESEQUENCING                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CONCEPT:                                                       │
│  Transition from one section to another in time                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │    Intro        Explore       Combat        Victory     │   │
│  │  ┌──────┐     ┌──────┐     ┌──────┐     ┌──────┐       │   │
│  │  │ A    │────▶│ B    │────▶│ C    │────▶│ D    │       │   │
│  │  └──────┘     └──────┘     └──────┘     └──────┘       │   │
│  │       │           ▲           │                         │   │
│  │       └───────────┴───────────┘                         │   │
│  │         (conditional transitions)                       │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  MARKERS:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │ DESTINATION MARKER                                      │   │
│  │ • Marks where playback can jump TO                     │   │
│  │ • Named entry points (e.g., "VerseStart")              │   │
│  │                                                         │   │
│  │ TRANSITION MARKER                                       │   │
│  │ • Marks where playback can jump FROM                   │   │
│  │ • Triggers jump to destination                         │   │
│  │                                                         │   │
│  │ TRANSITION REGION                                       │   │
│  │ • Range for bridge content                             │   │
│  │ • Plays between source and destination                 │   │
│  │ • Optional crossfade                                    │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  QUANTIZATION:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Immediate      - Jump now                             │   │
│  │ • Next Beat      - Wait for beat boundary              │   │
│  │ • Next Bar       - Wait for bar boundary               │   │
│  │ • Next Marker    - Wait for next transition marker     │   │
│  │ • Tempo Marker   - Align to tempo grid                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Vertical Layering

```
┌─────────────────────────────────────────────────────────────────┐
│                  VERTICAL LAYERING                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CONCEPT:                                                       │
│  Add/remove layers while playing the same musical piece         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Track 1 (Drums):      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓       │   │
│  │  Track 2 (Bass):       ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░       │   │
│  │  Track 3 (Strings):    ░░░░░░░░▓▓▓▓▓▓▓▓░░░░░░░░       │   │
│  │  Track 4 (Brass):      ░░░░░░░░░░░░▓▓▓▓░░░░░░░░       │   │
│  │                                                         │   │
│  │  Intensity Parameter:  0    25   50   75   100         │   │
│  │                                                         │   │
│  │  ░ = Volume 0 (silent)                                 │   │
│  │  ▓ = Volume 1 (playing)                                │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  IMPLEMENTATION:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Multi-track event with parallel audio                │   │
│  │ • Parameter controls track volumes                     │   │
│  │ • Automated volume curves per track                    │   │
│  │ • All tracks stay in sync                              │   │
│  │                                                         │   │
│  │ Parameter → Volume automation:                          │   │
│  │ Intensity 0-25:   Drums only                           │   │
│  │ Intensity 25-50:  Drums + Bass fade in                 │   │
│  │ Intensity 50-75:  + Strings fade in                    │   │
│  │ Intensity 75-100: + Brass fade in                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.3 Tempo System

```
┌─────────────────────────────────────────────────────────────────┐
│                    TEMPO MARKERS                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TEMPO MARKER:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Defines BPM at a point in timeline                   │   │
│  │ • Affects transition quantization                       │   │
│  │ • Used for beat-sync calculations                       │   │
│  │                                                         │   │
│  │ Properties:                                             │   │
│  │ - BPM (tempo)                                           │   │
│  │ - Time signature (4/4, 3/4, etc.)                      │   │
│  │ - Bar position                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  TEMPO AUTOMATION:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Gradual tempo changes                                 │   │
│  │ • Ritardando / Accelerando                             │   │
│  │ • Match gameplay speed changes                          │   │
│  │                                                         │   │
│  │ Note: When tempo changes, transition/destination       │   │
│  │       markers move with their bar/beat positions       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. PLUGIN DEVELOPMENT

### 9.1 Plugin Types

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMOD PLUGIN TYPES                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  EFFECT PLUGINS:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Process audio input                                   │   │
│  │ • Insert in DSP chain                                   │   │
│  │ • Parameters controllable from Studio                   │   │
│  │                                                         │   │
│  │ Subtypes:                                               │   │
│  │ - Standard effects (EQ, compression, etc.)             │   │
│  │ - Up/down-mixing (panning, reverb)                     │   │
│  │ - Spatialization (3D panning, HRTF)                    │   │
│  │ - Sidechain (compressor, modulation)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SOUND MODULE PLUGINS:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Generate audio (no input)                             │   │
│  │ • Synthesis, procedural audio                           │   │
│  │ • Place on tracks in events                             │   │
│  │ • Trigger from timeline or parameters                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CODEC PLUGINS:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Custom file format support                            │   │
│  │ • Decode callbacks                                      │   │
│  │ • Metadata reading                                      │   │
│  │ • Can be DLL or compiled-in                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  OUTPUT PLUGINS:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Custom audio output                                   │   │
│  │ • Network streaming                                     │   │
│  │ • Recording                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 9.2 DSP Plugin Structure

```cpp
// FMOD DSP Plugin Development

// Plugin descriptor
FMOD_DSP_DESCRIPTION myPluginDesc = {
    FMOD_PLUGIN_SDK_VERSION,
    "My Plugin",                    // Name
    0x00010000,                     // Version
    1,                              // Input buffers
    1,                              // Output buffers
    create_callback,
    release_callback,
    reset_callback,
    nullptr,                        // Read callback (optional)
    process_callback,               // Main processing
    nullptr,                        // setPosition (optional)
    NUM_PARAMETERS,
    myParamDescs,                   // Parameter descriptions
    setparam_float_callback,
    setparam_int_callback,
    setparam_bool_callback,
    setparam_data_callback,
    getparam_float_callback,
    getparam_int_callback,
    getparam_bool_callback,
    getparam_data_callback,
    nullptr,                        // shouldiprocess (optional)
    nullptr,                        // userdata
    sys_register_callback,
    sys_deregister_callback,
    nullptr                         // Mix callback (optional)
};

// Parameter types
// - FMOD_DSP_PARAMETER_TYPE_FLOAT  → Dials in Studio
// - FMOD_DSP_PARAMETER_TYPE_INT    → Discrete values
// - FMOD_DSP_PARAMETER_TYPE_BOOL   → Buttons in Studio
// - FMOD_DSP_PARAMETER_TYPE_DATA   → Custom data

// Processing callback
FMOD_RESULT F_CALLBACK process_callback(
    FMOD_DSP_STATE* dsp_state,
    unsigned int length,
    const FMOD_DSP_BUFFER_ARRAY* inbufferarray,
    FMOD_DSP_BUFFER_ARRAY* outbufferarray,
    FMOD_BOOL inputsidle,
    FMOD_DSP_PROCESS_OPERATION op)
{
    if (op == FMOD_DSP_PROCESS_QUERY) {
        // Query phase - return capabilities
        return FMOD_OK;
    }

    // Process phase
    MyPluginData* data = (MyPluginData*)dsp_state->plugindata;

    float* inbuf = inbufferarray->buffers[0];
    float* outbuf = outbufferarray->buffers[0];
    int channels = inbufferarray->buffernumchannels[0];

    // Apply gain with smoothing
    float targetGain = data->params.gain;
    float currentGain = data->currentGain;

    for (unsigned int i = 0; i < length * channels; i++) {
        // Smooth parameter changes
        currentGain += (targetGain - currentGain) * 0.001f;
        outbuf[i] = inbuf[i] * currentGain;
    }

    data->currentGain = currentGain;
    return FMOD_OK;
}
```

### 9.3 Plugin Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                  PLUGIN DEPLOYMENT                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FMOD STUDIO (Authoring):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Windows:  32-bit DLL (even on 64-bit OS)               │   │
│  │ macOS:    dylib                                         │   │
│  │                                                         │   │
│  │ Location: FMOD Studio/Plugins/                         │   │
│  │                                                         │   │
│  │ Note: Studio itself is 32-bit on some platforms        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  GAME RUNTIME:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Options:                                                │   │
│  │ 1. Dynamic library (DLL/so/dylib)                      │   │
│  │ 2. Static library                                       │   │
│  │ 3. Compiled directly with game code                    │   │
│  │                                                         │   │
│  │ Loading:                                                │   │
│  │ System::loadPlugin() for dynamic                       │   │
│  │ System::registerDSP() for static/compiled              │   │
│  │                                                         │   │
│  │ IMPORTANT: Load plugin BEFORE loading banks/events     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PLATFORM BUILDS:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Windows:     x86/x64 DLL                               │   │
│  │ PlayStation: Static library (PRX for PS4)              │   │
│  │ Xbox:        Static library                            │   │
│  │ Switch:      Static library                            │   │
│  │ Mobile:      Compiled with app                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. PROFILER AND DEBUGGING

### 10.1 Profiler Features

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMOD STUDIO PROFILER                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SESSION MANAGEMENT:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Record profiling sessions                             │   │
│  │ • Save/load sessions                                    │   │
│  │ • Export for sharing (Package Selection)               │   │
│  │ • Organize in folders                                   │   │
│  │ • Compare sessions                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  OVERVIEW PANE:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Active event instances                                │   │
│  │ • Active snapshots with intensity                       │   │
│  │ • Global parameters                                     │   │
│  │ • 3D view of sound positions                           │   │
│  │                                                         │   │
│  │ Snapshot display:                                       │   │
│  │ • Playing = light gray border                          │   │
│  │ • Stopped = no border (visible 8 seconds)              │   │
│  │ • Intensity percentage shown                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  EVENT TRACKS:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Timeline view of event playback                      │   │
│  │ • Start/stop visualization                             │   │
│  │ • Parameter value over time                            │   │
│  │                                                         │   │
│  │ Auto-add options:                                       │   │
│  │ • While recording                                       │   │
│  │ • After recording                                       │   │
│  │ • Only when explicitly added                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 Live Update

```
┌─────────────────────────────────────────────────────────────────┐
│                    LIVE UPDATE                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PURPOSE:                                                       │
│  • Edit events while game is running                            │
│  • Real-time parameter tweaking                                 │
│  • Immediate feedback on changes                                │
│  • Debug audio issues in context                                │
│                                                                  │
│  SETUP:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Game code:                                              │   │
│  │                                                         │   │
│  │ // Enable live update                                   │   │
│  │ FMOD_STUDIO_INITFLAGS flags =                          │   │
│  │     FMOD_STUDIO_INIT_LIVEUPDATE;                       │   │
│  │                                                         │   │
│  │ // Enable profiling                                     │   │
│  │ FMOD_INITFLAGS coreFlags =                             │   │
│  │     FMOD_INIT_NORMAL | FMOD_INIT_PROFILE_ENABLE;       │   │
│  │                                                         │   │
│  │ Studio::System::initialize(..., flags, coreFlags);     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CONNECTING:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 1. Game running with LIVEUPDATE flag                   │   │
│  │ 2. FMOD Studio → File → Connect to Game                │   │
│  │ 3. Enter IP address (localhost for local)              │   │
│  │ 4. Studio connects via network                         │   │
│  │                                                         │   │
│  │ Port requirements:                                      │   │
│  │ • Default port must be open                            │   │
│  │ • Console dev kits need port configuration             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CAPABILITIES:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ✓ Modify event properties                              │   │
│  │ ✓ Adjust mixer settings                                │   │
│  │ ✓ Change effect parameters                             │   │
│  │ ✓ Profile performance                                   │   │
│  │ ✓ Monitor active events                                │   │
│  │                                                         │   │
│  │ ✗ Add new events (requires rebuild)                    │   │
│  │ ✗ Change bank structure                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. PLATFORM SUPPORT

### 11.1 Platform Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMOD PLATFORM SUPPORT                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ Platform          │ HW Codec │ Spatial    │ Notes          ││
│  │ ──────────────────┼──────────┼────────────┼────────────────││
│  │ Windows           │ -        │ Sonic/Atmos│ WASAPI         ││
│  │ PlayStation 5     │ AT9,Opus │ Tempest    │ ACM convolution││
│  │ PlayStation 4     │ AT9      │ 3D audio   │ PRX support    ││
│  │ Xbox Series X|S   │ XMA2     │ Atmos      │ XDSP convol.   ││
│  │ Xbox One          │ XMA2     │ Atmos      │ Sonic support  ││
│  │ Nintendo Switch   │ ADPCM,Opus│ -         │ Native audio   ││
│  │ iOS               │ AAC      │ -          │ AVAudioEngine  ││
│  │ Android           │ -        │ -          │ AAudio/OpenSL  ││
│  │ macOS             │ -        │ -          │ CoreAudio      ││
│  │ Linux             │ -        │ -          │ PulseAudio     ││
│  │ tvOS              │ AAC      │ -          │               ││
│  │ HTML5             │ -        │ -          │ WebAudio      ││
│  │ Stadia            │ -        │ -          │ Deprecated     ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  BANK DIRECTORIES:                                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ PS5:           Banks/PS5/                                  ││
│  │ Xbox Series:   Banks/Scarlett/                             ││
│  │ Switch:        Banks/Switch/                               ││
│  │ Desktop:       Banks/Desktop/                              ││
│  │ Mobile:        Banks/Mobile/                               ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 11.2 Engine Integrations

```
┌─────────────────────────────────────────────────────────────────┐
│                  ENGINE INTEGRATIONS                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  UNREAL ENGINE:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Official FMOD for Unreal plugin                       │   │
│  │ • Blueprint support                                     │   │
│  │ • Actor components                                      │   │
│  │ • Sequencer integration                                 │   │
│  │ • Automatic bank loading                                │   │
│  │ • Reverb volume support                                 │   │
│  │                                                         │   │
│  │ Note: PS5 requires engine modification for            │   │
│  │       Unreal built-in audio replacement                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  UNITY:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Official FMOD for Unity plugin                        │   │
│  │ • C# API wrapper                                        │   │
│  │ • StudioEventEmitter component                         │   │
│  │ • StudioListener component                              │   │
│  │ • Automatic platform switching                          │   │
│  │ • Timeline integration                                  │   │
│  │ • Addressables support                                  │   │
│  │                                                         │   │
│  │ Tips:                                                   │   │
│  │ - Control native music player on mobile                │   │
│  │ - IsInitialized property for safe checks               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  GODOT:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Community GDNative extension                          │   │
│  │ • fmod-gdextension (Godot 4.x)                         │   │
│  │ • Full Studio API support                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CUSTOM ENGINES:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • C/C++ API                                             │   │
│  │ • C# bindings available                                 │   │
│  │ • Example code provided                                 │   │
│  │ • Comprehensive documentation                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 12. MEMORY INITIALIZATION

### 12.1 Memory System

```cpp
// FMOD Memory Initialization

// Option 1: FMOD manages memory (default)
FMOD::System_Create(&system);
system->init(...);

// Option 2: Custom memory pool
void* pool = myAllocator.allocate(poolSize);  // Must be 512-byte aligned

FMOD_ADVANCEDSETTINGS settings = {};
settings.cbSize = sizeof(FMOD_ADVANCEDSETTINGS);

FMOD::Memory_Initialize(
    pool,           // Memory pool pointer
    poolSize,       // Pool size (multiple of 512)
    nullptr,        // malloc callback (mutually exclusive with pool)
    nullptr,        // realloc callback
    nullptr,        // free callback
    FMOD_MEMORY_NORMAL
);

// Option 3: Custom allocators
FMOD::Memory_Initialize(
    nullptr,        // No pool
    0,              // No pool size
    myMalloc,       // Custom malloc
    myRealloc,      // Custom realloc
    myFree,         // Custom free
    FMOD_MEMORY_NORMAL
);

// IMPORTANT: Call BEFORE creating any FMOD System object
```

### 12.2 Codec Memory

```
┌─────────────────────────────────────────────────────────────────┐
│                  CODEC MEMORY USAGE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Per-voice instance memory:                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ADPCM/FADPCM:   3,128 bytes                            │   │
│  │ Vorbis:        23,256 bytes                            │   │
│  │ MP3:           Varies (~20KB)                          │   │
│  │ Opus:          Varies (~30KB)                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Default simultaneous channels:                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ADPCM:  32 channels                                    │   │
│  │ Vorbis: Limited by voice count                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  These limits determine max simultaneous compressed playback    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 13. BEST PRACTICES

### 13.1 Performance Guidelines

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMOD BEST PRACTICES                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  VOICE MANAGEMENT:                                              │
│  ✓ Set realistic real voice limit (32-64)                      │
│  ✓ Use generous virtual voice limit (512-1024)                 │
│  ✓ Set priorities on important sounds                          │
│  ✓ Use distance attenuation to reduce audible voices          │
│                                                                  │
│  LOADING:                                                       │
│  ✓ Stream music and long ambiences                             │
│  ✓ Use compressed samples for frequent sounds                  │
│  ✓ Use FSB format for optimized loading                        │
│  ✓ Pre-load critical sounds                                    │
│  ✓ Unload unused banks                                          │
│                                                                  │
│  CODECS:                                                        │
│  ✓ FADPCM for mobile and high-polyphony                        │
│  ✓ Vorbis for quality-critical content                         │
│  ✓ Hardware codecs when available (AT9, XMA2)                  │
│  ✓ Match codec to content requirements                         │
│                                                                  │
│  DSP:                                                           │
│  ✓ Minimize DSP chain length                                   │
│  ✓ Use built-in effects when possible                          │
│  ✓ Bypass unused effects                                        │
│  ✓ Group sounds to share effects                               │
│                                                                  │
│  MEMORY:                                                        │
│  ✓ Use memory-point loading for large banks                    │
│  ✓ Profile memory usage regularly                              │
│  ✓ Split banks by level/area                                   │
│  ✓ Unload banks during loading screens                         │
│                                                                  │
│  LIVE UPDATE:                                                   │
│  ✓ Enable during development                                   │
│  ✓ Disable in shipping builds (unless needed)                  │
│  ✓ Use profiler to verify performance                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 14. LICENSING

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMOD LICENSING                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  NON-COMMERCIAL LICENSE:                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Free                                                  │   │
│  │ • For non-commercial distribution only                  │   │
│  │ • Educational, personal projects                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  INDIE LICENSE:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Budget < $600,000 USD                                 │   │
│  │ • Free until commercial release                         │   │
│  │ • Low per-title fee                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  BASIC LICENSE:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Budget $600,000 - $1,800,000 USD                     │   │
│  │ • Per-title licensing                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PREMIUM LICENSE:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Budget > $1,800,000 USD                              │   │
│  │ • Enterprise pricing                                    │   │
│  │ • Direct support                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 15. REFERENCES

### Official Documentation
- [FMOD Documentation](https://www.fmod.com/docs/2.02/api/welcome.html)
- [Core API Guide](https://www.fmod.com/docs/2.02/api/core-guide.html)
- [DSP Architecture White Paper](https://www.fmod.com/docs/2.02/api/white-papers-dsp-architecture.html)
- [Spatial Audio White Paper](https://www.fmod.com/docs/2.02/api/white-papers-spatial-audio.html)

### Integration Guides
- [FMOD for Unreal](https://fmod.com/docs/2.03/unreal/welcome.html)
- [FMOD for Unity](https://www.fmod.com/docs/2.02/unity/)
- [Platform Specifics](https://www.fmod.com/docs/2.02/unreal/platform-specifics.html)

### Plugin Development
- [Plugin API DSP](https://www.fmod.com/docs/2.02/api/plugin-api-dsp.html)
- [DSP Plugin API White Paper](https://fmod.com/resources/documentation-api?version=2.0&page=white-papers-dsp-plugin-api.html)

### Third-Party Integration
- [Steam Audio FMOD Integration](https://valvesoftware.github.io/steam-audio/doc/fmod/index.html)
- [Resonance Audio FMOD](https://resonance-audio.github.io/resonance-audio/develop/fmod/getting-started.html)

---

**Document Version:** 1.0
**Last Updated:** January 2026
**Analyst:** Claude (Chief Audio Architect / Lead DSP Engineer / Engine Architect)
