# Pro Tools 2024 — Ultra-Detaljna Tehnička Analiza

**Verzija:** 2024.10+ (oktobar 2024)
**Datum analize:** Januar 2026
**Svrha:** Referentni dokument za FluxForge Studio implementaciju

---

## SADRŽAJ

1. [Audio Engine Architecture](#1-audio-engine-architecture)
2. [DSP Processors (Stock Plugins)](#2-dsp-processors-stock-plugins)
3. [Mixer Architecture](#3-mixer-architecture)
4. [Timeline/Arrangement](#4-timelinearrangement)
5. [Editing Capabilities](#5-editing-capabilities)
6. [MIDI Capabilities](#6-midi-capabilities)
7. [Plugin Hosting](#7-plugin-hosting)
8. [Project/Session Management](#8-projectsession-management)
9. [Metering & Visualization](#9-metering--visualization)
10. [UI/UX Design](#10-uiux-design)
11. [Hardware Integration](#11-hardware-integration)
12. [Unique Features](#12-unique-features)

---

## 1. AUDIO ENGINE ARCHITECTURE

### 1.1 Native vs HDX Architecture

#### Native System
```
┌─────────────────────────────────────────────────────────────┐
│                    HOST CPU PROCESSING                       │
├─────────────────────────────────────────────────────────────┤
│  • AAX Native plugins koriste CPU računara                  │
│  • Latencija zavisi od buffer size postavke                 │
│  • Fleksibilna alokacija resursa                            │
│  • Dostupno u Pro Tools Artist/Studio/Ultimate              │
│  • Voices: do 128 (Artist), 256 (Studio), 512 (Ultimate)    │
└─────────────────────────────────────────────────────────────┘
```

#### HDX System
```
┌─────────────────────────────────────────────────────────────┐
│                   HDX CARD ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────┤
│  • 18 TI DSP procesora po kartici                           │
│  • 6.3 GHz ukupne procesne snage po kartici                 │
│  • 2 high-performance FPGA čipa                             │
│  • Dedicirana FPGA za mix bus (64-bit sumiranje)            │
│  • 256 voices po kartici @ 44.1/48kHz                       │
│  • 128 voices po kartici @ 88.2/96kHz                       │
│  • 64 voices po kartici @ 176.4/192kHz                      │
│  • Fiksna latencija: 0.7ms @ 96kHz (64 samples)             │
│  • Do 3 HDX kartice = 768 voices @ 48kHz                    │
└─────────────────────────────────────────────────────────────┘
```

#### Hybrid Engine (2022+)
```
┌─────────────────────────────────────────────────────────────┐
│                    HYBRID PROCESSING                         │
├─────────────────────────────────────────────────────────────┤
│  Kombinuje Native + DSP processing:                         │
│                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐            │
│  │   DSP    │ ←→  │  MIXER   │ ←→  │  NATIVE  │            │
│  │ (HDX)    │     │  ENGINE  │     │  (CPU)   │            │
│  └──────────┘     └──────────┘     └──────────┘            │
│                                                              │
│  • Toggle button za prebacivanje track-a DSP ↔ Native       │
│  • 2048 voices dostupno svim HDX korisnicima                │
│  • Seamless switching bez prekida audio stream-a            │
│  • DSP mode: ultra-low latency (0.7ms)                      │
│  • Native mode: fleksibilna procesna snaga                  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 AAX Native vs AAX DSP

| Karakteristika | AAX Native | AAX DSP |
|----------------|------------|---------|
| **Processing** | Host CPU | HDX DSP čipovi |
| **Latencija** | Varijabilna (buffer-dependent) | Fiksna (0.7ms @ 96kHz) |
| **Floating Point** | 32-bit / 64-bit | 32-bit |
| **Mix Bus** | 64-bit | 64-bit |
| **Matematika** | Identična | Identična |
| **Dostupnost** | Svi Pro Tools nivoi | Samo HDX sistemi |
| **Resource Management** | Dynamic | Dedicated |

**KRITIČNA ČINJENICA:** AAX Native i AAX DSP koriste identičnu floating-point matematiku — zvuk je ISTI. Jedina razlika je gde se processing odvija i latencija.

### 1.3 Sample Rates

```
Podržani Sample Rates:
├── 44.1 kHz  ─── CD standard, većina streaming servisa
├── 48.0 kHz  ─── Video/broadcast standard
├── 88.2 kHz  ─── 2x oversample od 44.1kHz
├── 96.0 kHz  ─── Professional hi-res audio
├── 176.4 kHz ─── 4x oversample od 44.1kHz
└── 192.0 kHz ─── Maximum supported (mastering, archival)

Voice Count Impact:
┌────────────────┬──────────┬──────────┬──────────┐
│ Sample Rate    │ HDX×1    │ HDX×2    │ HDX×3    │
├────────────────┼──────────┼──────────┼──────────┤
│ 44.1/48 kHz    │ 256      │ 512      │ 768      │
│ 88.2/96 kHz    │ 128      │ 256      │ 384      │
│ 176.4/192 kHz  │ 64       │ 128      │ 192      │
└────────────────┴──────────┴──────────┴──────────┘
```

### 1.4 Bit Depths

```
Recording Bit Depths:
├── 16-bit  ─── CD quality (96dB dynamic range)
├── 24-bit  ─── Professional standard (144dB dynamic range)
└── 32-bit float ─── Maximum headroom (1528dB theoretical)

Internal Processing:
├── Plugin processing: 32-bit floating point
├── Mix bus summing: 64-bit floating point
└── Dither options: POW-r, shaped noise, flat TPDF
```

**32-bit Float Prednosti:**
- Praktično nemoguće clipovati
- Može se recovervati ako signal premaši 0dB
- Clip Gain može vratiti oštećeni signal
- Ograničenje: Nije svi DAW-ovi čitaju 32-bit float

### 1.5 Buffer Sizes

```
Dostupni Buffer Sizes (samples):
├── 32    ─── Ultra-low latency (zahteva moćan CPU)
├── 64    ─── Very low latency (preporučeno za tracking)
├── 128   ─── Low latency (balans tracking/mixing)
├── 256   ─── Medium (good for mixing)
├── 512   ─── Higher (complex sessions)
├── 1024  ─── High (heavy plugin load)
├── 2048  ─── Very high (maximum plugin count)
└── 4096  ─── Maximum (offline processing)

Latency Formula:
Round-trip latency = (Buffer Size / Sample Rate) × 2 + Hardware latency

Primer @ 48kHz, 128 samples:
(128 / 48000) × 2 = 5.33ms round-trip (bez hardware latency)
```

### 1.6 Delay Compensation (ADC)

#### Automatic Delay Compensation
```
┌─────────────────────────────────────────────────────────────┐
│              AUTOMATIC DELAY COMPENSATION (ADC)              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Plugin reports latency → Pro Tools calculates total        │
│                              ↓                               │
│  Finds slowest path → Delays all other tracks to match      │
│                              ↓                               │
│  Result: Perfect phase alignment across all tracks          │
│                                                              │
│  Visualization in Mix Window:                                │
│  ┌─────────────────┐                                        │
│  │ Track 1: 100    │ ← Plugin latency (samples)            │
│  │ Comp:    100    │ ← Compensation applied                │
│  │ Status:  GREEN  │ ← Fully compensated                   │
│  └─────────────────┘                                        │
│                                                              │
│  Status Colors:                                              │
│  • GREEN  = Compensated correctly                           │
│  • ORANGE = Slowest track (reference)                       │
│  • RED    = Not compensated (problem!)                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Auto Low Latency Mode
- Automatski ON by default
- Kada track uđe u Record/Input Monitor mode → ADC se suspenduje za taj track
- Omogućava nisku latenciju za performer-a dok ostali trackovi ostaju kompenzovani
- Može se toggle-ovati u Playback Engine

### 1.7 Voice Allocation

```
Voice Allocation Hierarchy:

Dynamic Voice Allocation (Native):
├── Sistem automatski alocira voices prema potrebi
├── Trackovi višeg prioriteta (prvi u Edit window) dobijaju voices
└── Overflow trackovi se automatski mute-uju

HDX Voice Allocation:
├── Fiksna alokacija po kartici
├── 64 "skrivenih" voices po kartici za mixer routing
├── Prioritet: trackovi gore u Edit window ili levo u Mix window
└── Kada dostignete limit, niži trackovi ne sviraju

Voice Usage po Track Type:
├── Mono audio track      = 1 voice
├── Stereo audio track    = 2 voices
├── 5.1 surround track    = 6 voices
├── 7.1.4 Atmos track     = 12 voices
└── Auxiliary Input       = 0 voices (pass-through)

Native Plugin After DSP Plugin:
├── Dodaje voice cost za svaki kanal
├── Primer: 5.1 native plugin posle DSP = 12 extra voices
└── Razlog: Audio mora izaći iz DSP → Native processing
```

### 1.8 Dynamic Plugin Processing

```
┌─────────────────────────────────────────────────────────────┐
│              DYNAMIC PLUGIN PROCESSING                       │
├─────────────────────────────────────────────────────────────┤
│  Uvedeno u Pro Tools 11                                     │
│                                                              │
│  Kako radi:                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Audio       │ →  │ Plugin      │ →  │ DSP         │     │
│  │ Present     │    │ Active      │    │ Allocated   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ No Audio    │ →  │ Plugin      │ →  │ DSP         │     │
│  │ (Silence)   │    │ Bypassed    │    │ Released    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                              │
│  Ograničenja:                                                │
│  • Radi samo na Aux trackovima (ne Audio tracks)            │
│  • Audio track plugini ostaju aktivni čak i bez regiona    │
│  • Reverb/delay tail-ovi mogu biti odsečeni                 │
│                                                              │
│  Enable/Disable:                                             │
│  Setup → Playback Engine → Dynamic Plug-In Processing       │
└─────────────────────────────────────────────────────────────┘
```

### 1.9 Disk Caching

```
Disk Cache Modes:

Normal Mode:
├── Audio se čita direktno sa diska
├── Minimalna RAM upotreba
└── Zavisno od disk performansi

Disk Cache (RAM):
├── Audio fajlovi se učitavaju u RAM
├── Dramatično brži pristup
├── Veća RAM potrošnja
├── Preporučeno za SSD sisteme sa dovoljno RAM-a
└── Setup → Playback Engine → Cache Size

Cache Size Options:
├── Normal (default)
├── Large
├── Larger
└── Custom (GB specification)
```

---

## 2. DSP PROCESSORS (STOCK PLUGINS)

### 2.1 EQ III (7-Band Parametric)

```
┌─────────────────────────────────────────────────────────────┐
│                        EQ III 7-BAND                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Specifikacije:                                              │
│  • Rezolucija: 48-bit double precision                      │
│  • Sample rates: do 192kHz                                  │
│  • Latencija: Minimal (Linear phase nije podržan)           │
│  • Format: Mono, Stereo, Multi-mono, Surround               │
│                                                              │
│  Frequency Bands:                                            │
│  ┌────────┬────────────────────────────────────┐            │
│  │ HPF    │ High-Pass Filter (6dB/oct)         │            │
│  │ LF     │ Low Frequency (shelf/bell)         │            │
│  │ LMF    │ Low-Mid Frequency (bell)           │            │
│  │ MF     │ Mid Frequency (bell)               │            │
│  │ HMF    │ High-Mid Frequency (bell)          │            │
│  │ HF     │ High Frequency (shelf/bell)        │            │
│  │ LPF    │ Low-Pass Filter (6dB/oct)          │            │
│  └────────┴────────────────────────────────────┘            │
│                                                              │
│  Filter Types per Band:                                      │
│  • Bell (parametric) — fully parametric Q                   │
│  • Shelf (low/high) — variable Q shelving                   │
│  • Notch — variable Q notch filter                          │
│  • High-Pass — 6dB/octave, 12dB/octave, 18dB/octave        │
│  • Low-Pass — 6dB/octave, 12dB/octave, 18dB/octave         │
│                                                              │
│  Parametri po bandu:                                         │
│  • Frequency: 20Hz – 20kHz                                  │
│  • Gain: ±18dB                                              │
│  • Q: 0.1 – 10.0 (variable)                                 │
│  • Type: Bell/Shelf/Cut (band dependent)                    │
│                                                              │
│  Konfigurcije:                                               │
│  • EQ III 1-Band — Minimal CPU, single band                 │
│  • EQ III 4-Band — LF, LMF/MF, HMF, HF                      │
│  • EQ III 7-Band — Full featured                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Channel Strip

```
┌─────────────────────────────────────────────────────────────┐
│                   AVID CHANNEL STRIP                         │
├─────────────────────────────────────────────────────────────┤
│  Poreklo: Euphonix System 5 console design                  │
│                                                              │
│  Signal Flow:                                                │
│  Input → HPF → EQ → Dynamics → Output                       │
│                                                              │
│  SEKCIJE:                                                    │
│                                                              │
│  1. INPUT SECTION                                            │
│     ├── Input Gain: ±24dB                                   │
│     ├── Phase Invert                                        │
│     └── High-Pass Filter: 20Hz-500Hz, 12dB/oct             │
│                                                              │
│  2. EQ SECTION (4-band)                                      │
│     ├── LF: 30Hz-450Hz, ±20dB, shelf/bell                  │
│     ├── LMF: 50Hz-3kHz, ±20dB, bell                        │
│     ├── HMF: 500Hz-12kHz, ±20dB, bell                      │
│     ├── HF: 1.5kHz-16kHz, ±20dB, shelf/bell                │
│     └── Q: 0.5-5.0 (all bands)                              │
│                                                              │
│  3. DYNAMICS SECTION                                         │
│     ├── Expander/Gate:                                      │
│     │   ├── Threshold: -60dB to 0dB                        │
│     │   ├── Range: 0-80dB                                  │
│     │   ├── Ratio: 1:1 to 10:1                             │
│     │   ├── Attack: 10μs to 100ms                          │
│     │   └── Release: 10ms to 1s                            │
│     │                                                        │
│     └── Compressor:                                          │
│         ├── Threshold: -60dB to 0dB                        │
│         ├── Ratio: 1:1 to 20:1                             │
│         ├── Attack: 10μs to 100ms                          │
│         ├── Release: 10ms to 1s                            │
│         ├── Knee: 0-30dB (soft knee)                       │
│         └── Makeup Gain: 0-40dB                            │
│                                                              │
│  4. OUTPUT SECTION                                           │
│     ├── Output Gain: ±24dB                                  │
│     └── Limiter: On/Off with ceiling                        │
│                                                              │
│  Sidechain: External key input (mono)                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Dynamics III Suite

```
┌─────────────────────────────────────────────────────────────┐
│                    DYNAMICS III SUITE                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  A) COMPRESSOR/LIMITER                                       │
│  ───────────────────                                         │
│  ┌─────────────────────────────────────────┐                │
│  │ Threshold  │ -60dB to +6dB              │                │
│  │ Ratio      │ 1:1 to 100:1 (∞:1 limiter) │                │
│  │ Attack     │ 10μs to 200ms              │                │
│  │ Release    │ 5ms to 4 seconds           │                │
│  │ Knee       │ 0dB (hard) to 30dB (soft)  │                │
│  │ Gain       │ 0 to +40dB makeup          │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
│  Sidechain Features:                                         │
│  • External Key Input (mono)                                │
│  • Sidechain EQ (HPF, LPF, band filters)                   │
│  • Key Listen mode                                          │
│                                                              │
│  B) EXPANDER/GATE                                            │
│  ─────────────────                                           │
│  ┌─────────────────────────────────────────┐                │
│  │ Threshold  │ -60dB to 0dB               │                │
│  │ Ratio      │ 1:1 to 10:1 (expander)     │                │
│  │            │ 10:1+ = gate behavior      │                │
│  │ Range      │ 0dB to -80dB               │                │
│  │ Attack     │ 10μs to 200ms              │                │
│  │ Hold       │ 5ms to 4 seconds           │                │
│  │ Release    │ 5ms to 4 seconds           │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
│  C) DE-ESSER                                                 │
│  ───────────                                                 │
│  ┌─────────────────────────────────────────┐                │
│  │ Frequency  │ 800Hz to 12kHz             │                │
│  │ Range      │ 0dB to -20dB reduction     │                │
│  │ HF Only    │ Process only sibilants     │                │
│  │ Listen     │ Audition detection band    │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
│  Formati: Mono, Stereo, Multi-mono, Surround (do 7.1)      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 Reverbs

```
┌─────────────────────────────────────────────────────────────┐
│                      REVERB PLUGINS                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  A) D-VERB (Classic Stock Reverb)                           │
│  ────────────────────────────────                           │
│  Algorithms:                                                 │
│  ├── Hall — Large concert hall simulation                   │
│  ├── Church — Diffuse, long reverb                         │
│  ├── Plate — Classic plate reverb emulation                │
│  ├── Room 1 — Small room                                   │
│  ├── Room 2 — Medium room                                  │
│  ├── Ambient — Short, subtle ambience                      │
│  └── Non-Linear — Gated/reverse effects                    │
│                                                              │
│  Parametri:                                                  │
│  ├── Size: Small, Medium, Large                            │
│  ├── Diffusion: 0-100%                                     │
│  ├── Decay: 0.1s to infinite                               │
│  ├── Pre-Delay: 0-200ms                                    │
│  ├── HF Cut: 1kHz-16kHz                                    │
│  ├── LP Filter: On/Off                                     │
│  └── Mix: 0-100% wet                                       │
│                                                              │
│  B) AIR REVERB COLLECTION                                    │
│  ────────────────────────                                    │
│                                                              │
│  AIR Spring Reverb:                                          │
│  ├── Classic spring tank emulation                         │
│  ├── Parameters: Tension, Diffusion, Mix                   │
│  └── Ideal for: Guitar, vintage sounds                     │
│                                                              │
│  AIR Non-Linear Reverb:                                      │
│  ├── Gated reverb effects                                  │
│  ├── Reverse reverb                                        │
│  ├── Parameters: Shape, Time, Mix                          │
│  └── Ideal for: Drums, special effects                     │
│                                                              │
│  AIR Reverb:                                                 │
│  ├── Algorithmic reverb                                    │
│  ├── Multiple room types                                   │
│  └── Full parametric control                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.5 Delays

```
┌─────────────────────────────────────────────────────────────┐
│                       DELAY PLUGINS                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  A) MOD DELAY III                                            │
│  ─────────────────                                           │
│  Configurations:                                             │
│  ├── Mono                                                   │
│  ├── Mono-to-Stereo                                        │
│  ├── Stereo                                                │
│  └── Multi-mono                                            │
│                                                              │
│  Parametri:                                                  │
│  ├── Delay Time: 0ms to 4000ms (ili sync to tempo)         │
│  ├── Feedback: 0-100%                                      │
│  ├── LPF: 200Hz-20kHz                                      │
│  ├── Depth: Modulation amount                              │
│  ├── Rate: Modulation speed                                │
│  └── Mix: Dry/Wet balance                                  │
│                                                              │
│  Tempo Sync Values:                                          │
│  1/64, 1/32, 1/16, 1/8, 1/4, 1/2, 1/1                      │
│  + Dotted i Triplet varijante                              │
│                                                              │
│  B) AIR DELAY COLLECTION                                     │
│  ────────────────────────                                    │
│                                                              │
│  AIR Multi-Delay:                                            │
│  ├── 5 nezavisnih delay linija                             │
│  ├── Per-tap: Time, Pan, Level, Feedback                   │
│  ├── Global: Mix, Filter, Sync                             │
│  └── Ideal za: Complex rhythmic delays                     │
│                                                              │
│  AIR Dynamic Delay:                                          │
│  ├── Envelope follower modulation                          │
│  ├── Ducking delay effect                                  │
│  ├── Tempo sync                                            │
│  └── Ideal za: Vocals, clean delays                        │
│                                                              │
│  BBD Delay:                                                  │
│  ├── Analog bucket-brigade emulation                       │
│  ├── Lo-fi character                                       │
│  └── Ideal za: Vintage, lo-fi sounds                       │
│                                                              │
│  Tape Echo:                                                  │
│  ├── Analog tape delay emulation                           │
│  ├── Wow/Flutter control                                   │
│  ├── Saturation                                            │
│  └── Ideal za: Warm, vintage delays                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.6 Pro Tools-Specific: Elastic Audio & Clip Gain

```
┌─────────────────────────────────────────────────────────────┐
│                   ELASTIC AUDIO SYSTEM                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Elastic Audio Algorithms (Real-Time):                       │
│                                                              │
│  1. POLYPHONIC                                               │
│     ├── Za: Complex harmonic material, full mixes          │
│     ├── Preserves: Harmonic relationships                  │
│     ├── Best for: Guitars, pianos, orchestras              │
│     └── CPU: High                                          │
│                                                              │
│  2. RHYTHMIC                                                 │
│     ├── Za: Percussive material                            │
│     ├── Preserves: Sharp transients                        │
│     ├── Best for: Drums, percussion                        │
│     └── CPU: Medium                                        │
│                                                              │
│  3. MONOPHONIC                                               │
│     ├── Za: Single-note sources                            │
│     ├── Preserves: Pitch stability, formants               │
│     ├── Best for: Vocals, bass, lead instruments           │
│     └── CPU: Medium                                        │
│                                                              │
│  4. VARISPEED                                                │
│     ├── Za: Tape machine emulation                         │
│     ├── Linked pitch/time (kao vinyl)                      │
│     ├── Best for: Creative effects, vinyl simulation       │
│     └── CPU: Low                                           │
│                                                              │
│  5. X-FORM (Rendered Only)                                   │
│     ├── Za: Highest quality time/pitch manipulation        │
│     ├── Offline processing (AudioSuite)                    │
│     ├── Best for: Critical material, mastering             │
│     └── CPU: N/A (offline)                                 │
│                                                              │
│  6. ELASTIQUE PRO (2023.3+)                                  │
│     ├── Zplane algorithm                                   │
│     ├── Superior quality to legacy algorithms              │
│     ├── Available in all Pro Tools tiers                   │
│     └── CPU: Medium-High                                   │
│                                                              │
│  Elastic Properties:                                         │
│  ├── Time Stretch Factor                                   │
│  ├── Pitch Shift (semitones + cents)                       │
│  ├── Event Sensitivity (transient detection)               │
│  └── Warp markers (manual timing adjustment)               │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                       CLIP GAIN                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Clip Gain Line:                                             │
│  ├── Visual gain envelope na svakom clipu                  │
│  ├── Pre-insert gain adjustment                            │
│  ├── Non-destructive                                       │
│  └── Range: -144dB to +36dB                                │
│                                                              │
│  Keyboard Shortcuts:                                         │
│  ├── Ctrl+Shift+- : Show/hide clip gain line               │
│  ├── Ctrl+Shift+= : Show/hide clip gain info               │
│  ├── Ctrl+Shift+↑/↓ : Nudge clip gain up/down             │
│  ├── Ctrl+Shift+B : Clear clip gain to 0dB                 │
│  └── Ctrl+Shift+X : Cut clip gain                          │
│                                                              │
│  Workflow:                                                   │
│  ├── Ideal for: Pre-compression level matching             │
│  ├── Vocal leveling before processing                      │
│  ├── Drum hit balancing                                    │
│  └── Dialogue normalization                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. MIXER ARCHITECTURE

### 3.1 Signal Flow

```
┌─────────────────────────────────────────────────────────────┐
│              PRO TOOLS MIXER SIGNAL FLOW                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  AUDIO TRACK Signal Flow:                                    │
│                                                              │
│  ┌──────────────┐                                           │
│  │ Audio File   │                                           │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Clip Gain    │ ← Pre-insert gain adjustment              │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Inserts A-E  │ ← PRE-FADER inserts (5 slots)            │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Sends A-E    │ ← PRE-FADER sends (5 slots)              │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Channel      │                                           │
│  │ Fader        │ ← Volume control                          │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Inserts F-J  │ ← POST-FADER inserts (5 slots)           │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Sends F-J    │ ← POST-FADER sends (5 slots)             │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Pan          │ ← Stereo/surround positioning            │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Output       │ → Bus, Output, or Direct Out             │
│  └──────────────┘                                           │
│                                                              │
│  MASTER FADER Signal Flow (DIFFERENT!):                      │
│                                                              │
│  ┌──────────────┐                                           │
│  │ Mix Input    │                                           │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Fader        │ ← Volume FIRST                           │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Inserts A-J  │ ← POST-FADER (all 10 slots!)             │
│  └──────┬───────┘                                           │
│         ↓                                                    │
│  ┌──────────────┐                                           │
│  │ Output       │                                           │
│  └──────────────┘                                           │
│                                                              │
│  KRITIČNA NAPOMENA:                                          │
│  Master Fader inserti su POST-FADER! Ovo znači:             │
│  • Limiter/compressor na Master Fader će reagovati         │
│    na fader pokrete                                         │
│  • Za konzistentan mix bus processing, koristi              │
│    Aux Input track kao mix bus umesto Master Fader          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Insert Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    INSERT ARCHITECTURE                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Insert Slots per Track: 10 (A through J)                   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    PRE-FADER                         │    │
│  │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                     │    │
│  │  │ A │ │ B │ │ C │ │ D │ │ E │                     │    │
│  │  └───┘ └───┘ └───┘ └───┘ └───┘                     │    │
│  │  Signal pre volume fader-a                          │    │
│  │  Ideal za: EQ, compression, gates                   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                   POST-FADER                         │    │
│  │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                     │    │
│  │  │ F │ │ G │ │ H │ │ I │ │ J │                     │    │
│  │  └───┘ └───┘ └───┘ └───┘ └───┘                     │    │
│  │  Signal post volume fader-a                         │    │
│  │  Ideal za: Saturation, special effects              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Insert Types:                                               │
│  ├── AAX Native Plugin                                      │
│  ├── AAX DSP Plugin (HDX only)                             │
│  └── Hardware Insert (I/O → External → I/O)                │
│                                                              │
│  Hardware Insert Setup:                                      │
│  1. Define in I/O Setup → Insert tab                        │
│  2. Assign Interface Output + Input pair                    │
│  3. Insert responds like a plugin                           │
│  4. Manual latency compensation may be needed               │
│                                                              │
│  Multi-Mono Support:                                         │
│  • Stereo track može koristiti mono plugin                  │
│  • Link button kontroliše L/R parameter linking             │
│  • Unlinked omogućava nezavisna podešavanja                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Auxiliary Inputs

```
┌─────────────────────────────────────────────────────────────┐
│                   AUXILIARY INPUT TRACKS                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Svrhe:                                                      │
│  ├── Effects returns (reverb, delay)                        │
│  ├── Submix/stem creation                                   │
│  ├── Parallel processing (NY compression)                   │
│  ├── External audio monitoring                              │
│  ├── VCA-like grouping (pre-VCA era)                       │
│  └── Sidechain signal routing                               │
│                                                              │
│  Karakteristike:                                             │
│  ├── Nema audio recording capability                        │
│  ├── Koristi 0 voices (pass-through)                        │
│  ├── Full insert chain (10 slots)                           │
│  ├── Full send capability (10 sends)                        │
│  └── Can be input for other tracks                          │
│                                                              │
│  Tipična podešavanja:                                        │
│                                                              │
│  Effects Return:                                             │
│  ┌──────────────┐                                           │
│  │ Input: Bus 1 │ ← Prima signal od Sends                  │
│  │ Inserts: Reverb/Delay plugin                            │
│  │ Output: Main Mix │                                       │
│  └──────────────┘                                           │
│                                                              │
│  Submix:                                                     │
│  ┌──────────────┐                                           │
│  │ Input: Drum Bus │ ← Prima od drum track outputs         │
│  │ Inserts: Bus compression, EQ                            │
│  │ Output: Main Mix │                                       │
│  └──────────────┘                                           │
│                                                              │
│  Parallel Processing:                                        │
│  ┌──────────────┐                                           │
│  │ Input: Same bus as dry signal                           │
│  │ Inserts: Heavy compression                              │
│  │ Output: Main Mix (blend with dry)                       │
│  └──────────────┘                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 VCA Masters

```
┌─────────────────────────────────────────────────────────────┐
│                      VCA MASTER TRACKS                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Voltage Controlled Amplifier (virtualni):                   │
│                                                              │
│  Kako radi:                                                  │
│  ┌────────────────────────────────────────────────┐         │
│  │                                                 │         │
│  │  Track 1 ─┐                                    │         │
│  │  Track 2 ─┼── Assigned to VCA Group ──→ VCA   │         │
│  │  Track 3 ─┘                            Master │         │
│  │                                                 │         │
│  │  VCA Fader movement scales all assigned        │         │
│  │  track faders proportionally                   │         │
│  │                                                 │         │
│  └────────────────────────────────────────────────┘         │
│                                                              │
│  Karakteristike:                                             │
│  ├── NE procesira audio (kontrola samo)                     │
│  ├── NE menja signal flow                                   │
│  ├── Track faders se pomeraju vizuelno                      │
│  ├── Relative fader relationships ostaju                    │
│  ├── Automation se može pisati na VCA                       │
│  └── Solo/Mute afektira sve članove grupe                   │
│                                                              │
│  VCA vs Aux Submix:                                          │
│  ┌─────────────────┬────────────────────────────┐           │
│  │ VCA             │ Aux Submix                 │           │
│  ├─────────────────┼────────────────────────────┤           │
│  │ No audio path   │ Audio passes through       │           │
│  │ No inserts      │ Has insert slots           │           │
│  │ No voice usage  │ Uses voices                │           │
│  │ Fader scaling   │ Actual gain stage          │           │
│  │ Individual      │ Combined signal            │           │
│  │ automation      │                            │           │
│  │ preserved       │                            │           │
│  └─────────────────┴────────────────────────────┘           │
│                                                              │
│  Best Practice:                                              │
│  • Koristi VCA za level control grupe                       │
│  • Koristi Aux za group processing                          │
│  • Kombinuj: VCA kontroliše tracks koji idu u Aux           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.5 Master Faders

```
┌─────────────────────────────────────────────────────────────┐
│                     MASTER FADER TRACKS                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Svrha:                                                      │
│  ├── Monitor output level                                   │
│  ├── Metering na output bus-u                               │
│  ├── Dithering (post-fader insert)                          │
│  └── Final limiting (post-fader insert)                     │
│                                                              │
│  KRITIČNO — Razlike od ostalih track tipova:                 │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ 1. Svi inserti su POST-FADER                        │    │
│  │    • Limiter reaguje na fader pokrete               │    │
│  │    • Dither ostaje na ispravnom mestu (last)        │    │
│  │                                                      │    │
│  │ 2. Nema pre-fader sends                              │    │
│  │                                                      │    │
│  │ 3. Nema input selector                               │    │
│  │    • Automatski mapira na output path               │    │
│  │                                                      │    │
│  │ 4. Nema pan control                                  │    │
│  │    • Stereo/surround defined by path                │    │
│  │                                                      │    │
│  │ 5. Može se assignovati bilo kojem output bus-u      │    │
│  │    • Múltiple Master Faders za različite outpute    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Preporučena praksa:                                         │
│  ├── UVEK imaj Master Fader na main output                  │
│  ├── Koristi za visual metering čak i ako je na 0dB        │
│  ├── Za mix bus processing → koristi Aux umesto MF          │
│  └── Dither plugin uvek na LAST insert slot                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.6 Bus Routing

```
┌─────────────────────────────────────────────────────────────┐
│                      BUS ROUTING SYSTEM                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Dva tipa Bus-eva:                                           │
│                                                              │
│  1. INTERNAL MIX BUSES                                       │
│     ├── Interni signal paths                                │
│     ├── Za routing između trackova                          │
│     ├── Neograničen broj (praktično)                        │
│     └── Ne koriste I/O resurse                              │
│                                                              │
│  2. OUTPUT BUSES                                             │
│     ├── Mapirani na hardware outputs                        │
│     ├── Defined in I/O Setup → Output tab                   │
│     └── Limited by interface I/O count                      │
│                                                              │
│  Routing Workflow:                                           │
│                                                              │
│  Via Track Output:                                           │
│  Track Output Selector → Bus → [Bus Name]                   │
│                                                              │
│  Via Send:                                                   │
│  Send Selector → Bus → [Bus Name]                           │
│  (Pre ili Post-fader zavisno od send position)              │
│                                                              │
│  I/O Setup — Bus Tab:                                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Path Name      │ Format  │ Mapping                  │    │
│  ├────────────────┼─────────┼──────────────────────────┤    │
│  │ Bus 1-2        │ Stereo  │ Internal                 │    │
│  │ Bus 3-4        │ Stereo  │ Internal                 │    │
│  │ Drum Bus       │ Stereo  │ Internal                 │    │
│  │ Reverb Send    │ Stereo  │ Internal                 │    │
│  │ Main Mix       │ Stereo  │ → Output 1-2            │    │
│  │ Headphones     │ Stereo  │ → Output 3-4            │    │
│  │ Atmos 7.1.4    │ 7.1.4   │ → Output 1-12           │    │
│  └────────────────┴─────────┴──────────────────────────┘    │
│                                                              │
│  Path Coloring (2023.12+):                                   │
│  ├── Color-code Input, Output, Bus, Insert paths           │
│  ├── Visualni identification u Mix/Edit window             │
│  └── Assign u I/O Setup ili direktno na track              │
│                                                              │
│  Sidechain Routing:                                          │
│  ├── Plugin Key Input selector                              │
│  ├── Može primiti bilo koji bus signal                      │
│  ├── UVEK mono (bez obzira na track width)                 │
│  └── Koristi za: Ducking, triggered effects, de-essing     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.7 I/O Setup (Comprehensive)

```
┌─────────────────────────────────────────────────────────────┐
│                    I/O SETUP WINDOW                          │
├─────────────────────────────────────────────────────────────┤
│  Access: Setup → I/O...                                     │
│                                                              │
│  TABS:                                                       │
│                                                              │
│  1. INPUT Tab                                                │
│     ├── Define input paths from interface                   │
│     ├── Create mono, stereo, surround inputs                │
│     ├── Name paths for easy identification                  │
│     └── Create sub-paths from multichannel inputs           │
│                                                              │
│  2. OUTPUT Tab                                               │
│     ├── Define output paths to interface                    │
│     ├── Map buses to physical outputs                       │
│     └── Configure monitoring paths                          │
│                                                              │
│  3. BUS Tab                                                  │
│     ├── Create internal mix buses                           │
│     ├── Map output buses to hardware                        │
│     ├── Configure bus formats (mono→7.1.4)                 │
│     └── Color coding for visual organization                │
│                                                              │
│  4. INSERT Tab                                               │
│     ├── Define hardware insert paths                        │
│     ├── Pair interface output + input                       │
│     └── Set latency compensation values                     │
│                                                              │
│  5. MIC PREAMPS Tab (HD I/O only)                           │
│     ├── Remote control of HD I/O preamps                   │
│     └── Gain, phantom power, pad settings                   │
│                                                              │
│  6. H/W INSERT DELAY Tab                                     │
│     ├── Manual delay compensation                           │
│     ├── Per-insert sample delay setting                     │
│     └── For hardware that doesn't report latency            │
│                                                              │
│  Path Properties:                                            │
│  ├── Name: User-definable                                   │
│  ├── Format: Mono, Stereo, LCR, Quad, 5.0, 5.1, 7.1, etc.  │
│  ├── Mapping: Physical I/O assignment                       │
│  ├── Color: Visual identification (2023.12+)                │
│  └── Active/Inactive: Enable/disable path                   │
│                                                              │
│  Import/Export:                                              │
│  ├── Save I/O Settings as file                              │
│  ├── Import I/O Settings from file                          │
│  ├── Include in session templates                           │
│  └── "Default" button resets to interface defaults          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

*Dokument se nastavlja u Part 2...*
# Pro Tools 2024 — Ultra-Detaljna Tehnička Analiza (Part 2)

---

## 4. TIMELINE/ARRANGEMENT

### 4.1 Edit Window Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   EDIT WINDOW LAYOUT                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    TOOLBAR                             │  │
│  │  [Edit Modes] [Edit Tools] [Zoom] [Grid] [Nudge]      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                     RULERS                              │ │
│  │  [Bars|Beats] [Min:Sec] [Timecode] [Samples] [Markers] │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────┬───────────────────────────────────────────────┐ │
│  │        │                                                │ │
│  │ TRACK  │              TIMELINE                         │ │
│  │ LIST   │              (Audio/MIDI Clips)               │ │
│  │        │                                                │ │
│  │ [Name] │  ┌─────┐  ┌─────┐  ┌─────────────┐           │ │
│  │ [I/O]  │  │Clip1│  │Clip2│  │   Clip 3    │           │ │
│  │ [Vol]  │  └─────┘  └─────┘  └─────────────┘           │ │
│  │ [Pan]  │                                                │ │
│  │        │                                                │ │
│  └────────┴───────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   CLIP LIST                             │ │
│  │  (All clips/regions in session)                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Ruler Types:                                                │
│  ├── Bars|Beats: Muzički grid                              │
│  ├── Minutes:Seconds: Apsolutno vreme                      │
│  ├── Timecode: SMPTE (film/video sync)                     │
│  ├── Feet+Frames: Film footage                             │
│  ├── Samples: Sample-accurate                              │
│  ├── Markers: Memory locations/markers                     │
│  ├── Tempo: Tempo changes                                  │
│  ├── Meter: Time signature changes                         │
│  ├── Key: Key signature (MIDI)                             │
│  └── Chord: Chord symbols                                  │
│                                                              │
│  Track List Display Options:                                 │
│  ├── Waveform View (audio)                                 │
│  ├── Volume Graph                                          │
│  ├── Pan Graph                                             │
│  ├── Mute/Solo                                             │
│  ├── Send Levels                                           │
│  ├── Insert Assignments                                    │
│  └── Playlist View (comping)                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Track Types (Complete)

```
┌─────────────────────────────────────────────────────────────┐
│                   PRO TOOLS TRACK TYPES                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. AUDIO TRACK                                              │
│     ├── Jedini tip koji može RECORDATI audio                │
│     ├── Formats: Mono, Stereo, Multichannel (do 7.1.4)     │
│     ├── Features:                                           │
│     │   ├── Full insert chain (10 slots)                   │
│     │   ├── Full send capability (10 sends)                │
│     │   ├── Clip Gain                                      │
│     │   ├── Elastic Audio                                  │
│     │   ├── Playlists (comping)                            │
│     │   └── Automation (all parameters)                    │
│     └── Voice Usage: 1 per channel                         │
│                                                              │
│  2. AUXILIARY INPUT TRACK                                    │
│     ├── Signal routing i processing                         │
│     ├── NE može recordati                                   │
│     ├── Uses:                                               │
│     │   ├── Effects returns                                │
│     │   ├── Submixes                                       │
│     │   ├── External input monitoring                      │
│     │   └── Parallel processing                            │
│     └── Voice Usage: 0 (pass-through)                      │
│                                                              │
│  3. INSTRUMENT TRACK                                         │
│     ├── Kombinuje MIDI input + Audio output                 │
│     ├── Hosts Virtual Instruments                           │
│     ├── Features:                                           │
│     │   ├── MIDI recording/editing                         │
│     │   ├── Plugin instrument slot                         │
│     │   ├── Full insert chain (pre/post instrument)        │
│     │   ├── MIDI Playlists (2024.10+)                      │
│     │   └── Audio output processing                        │
│     └── Voice Usage: Depends on instrument output          │
│                                                              │
│  4. MIDI TRACK                                               │
│     ├── MIDI data samo (no audio)                           │
│     ├── Output: External MIDI ili internal routing          │
│     ├── Uses:                                               │
│     │   ├── External hardware synths                       │
│     │   ├── Multi-timbral VI routing                       │
│     │   └── MIDI to multiple destinations                  │
│     └── Voice Usage: 0                                     │
│                                                              │
│  5. MASTER FADER TRACK                                       │
│     ├── Output monitoring i metering                        │
│     ├── Post-fader inserts only                             │
│     ├── Nema input selector                                 │
│     ├── Nema pan                                            │
│     └── Voice Usage: 0                                     │
│                                                              │
│  6. VCA TRACK                                                │
│     ├── Voltage Controlled Amplifier (virtual)              │
│     ├── Kontroliše grupu track-ova                          │
│     ├── NE procesira audio                                  │
│     ├── Samo level/mute/solo control                        │
│     └── Voice Usage: 0                                     │
│                                                              │
│  7. FOLDER TRACK                                             │
│     │                                                        │
│     ├── BASIC FOLDER:                                       │
│     │   ├── Organizacija trackova                          │
│     │   ├── Collapse/expand                                │
│     │   └── No audio functionality                         │
│     │                                                        │
│     └── ROUTING FOLDER:                                     │
│         ├── Basic Folder + Aux funkcionalnost              │
│         ├── Može procesirati audio od contained tracks     │
│         └── Combines organization + submix                 │
│                                                              │
│  8. VIDEO TRACK                                              │
│     ├── Video playback (requires Video Engine)              │
│     ├── Online/Offline toggle                               │
│     ├── Supports: QuickTime, AVI, MXF                       │
│     ├── Timecode sync                                       │
│     └── Audio from video na separate Audio Track           │
│                                                              │
│  Track Formats (Channel Width):                              │
│  ┌─────────────┬────────────────────┬────────────┐         │
│  │ Format      │ Channels           │ Voices     │         │
│  ├─────────────┼────────────────────┼────────────┤         │
│  │ Mono        │ 1                  │ 1          │         │
│  │ Stereo      │ 2 (L, R)           │ 2          │         │
│  │ LCR         │ 3                  │ 3          │         │
│  │ Quad        │ 4                  │ 4          │         │
│  │ LCRS        │ 4                  │ 4          │         │
│  │ 5.0         │ 5                  │ 5          │         │
│  │ 5.1         │ 6                  │ 6          │         │
│  │ 6.1         │ 7                  │ 7          │         │
│  │ 7.0         │ 7                  │ 7          │         │
│  │ 7.1         │ 8                  │ 8          │         │
│  │ 7.0.2       │ 9                  │ 9          │         │
│  │ 5.1.2       │ 8                  │ 8          │         │
│  │ 7.1.2       │ 10                 │ 10         │         │
│  │ 5.1.4       │ 10                 │ 10         │         │
│  │ 7.1.4       │ 12                 │ 12         │         │
│  │ 9.1.6       │ 16                 │ 16         │         │
│  └─────────────┴────────────────────┴────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 Clip Types

```
┌─────────────────────────────────────────────────────────────┐
│                       CLIP TYPES                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. WHOLE FILE CLIP                                          │
│     ├── Referencira ceo audio fajl                          │
│     ├── Boundaries = file start/end                         │
│     └── Editing creates new clips (non-destructive)         │
│                                                              │
│  2. SUBSET CLIP                                              │
│     ├── Referencira deo parent fajla                        │
│     ├── Has boundaries within parent file                   │
│     └── Može se extend-ovati do parent granica             │
│                                                              │
│  3. CLIP GROUP                                               │
│     ├── Multiple clips grouped as one                       │
│     ├── Edit/move together                                  │
│     ├── Can span multiple tracks                            │
│     ├── Ungroup to access individual clips                  │
│     └── Maintains relative timing                           │
│                                                              │
│  4. MIDI CLIP                                                │
│     ├── Contains MIDI note/CC data                          │
│     ├── Editable in MIDI Editor                             │
│     ├── Can be time-stretched (non-audio)                   │
│     └── Quantize, transpose operations                      │
│                                                              │
│  Clip Properties:                                            │
│  ├── Name (editable)                                        │
│  ├── Length (bars/beats ili time)                           │
│  ├── Start/End points                                       │
│  ├── Sync Point (za spotting)                               │
│  ├── Clip Gain (-144dB to +36dB)                           │
│  ├── Elastic Audio properties                               │
│  ├── Fade In/Out                                            │
│  └── Color (user assignable)                                │
│                                                              │
│  Clip List (Region Bin):                                     │
│  ├── Shows all clips in session                             │
│  ├── Auto-created clips from edits                          │
│  ├── Sort by: Name, Time, Length, etc.                      │
│  ├── Find/Filter functionality                              │
│  ├── Commands Focus mode (type to jump)                     │
│  └── Clear unused clips (cleanup)                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.4 Fades (7 Curve Types + Shapes)

```
┌─────────────────────────────────────────────────────────────┐
│                    FADE SYSTEM                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Fade Types:                                                 │
│  ├── Fade In: Volume ramp at clip start                    │
│  ├── Fade Out: Volume ramp at clip end                     │
│  └── Crossfade: Overlap transition between clips           │
│                                                              │
│  Curve Shapes:                                               │
│                                                              │
│  1. STANDARD                                                 │
│     ┌────────────────────┐                                  │
│     │         ╱──────    │ Single continuous curve          │
│     │       ╱            │ General purpose                  │
│     │     ╱              │ Adjustable via curve editor      │
│     └────────────────────┘                                  │
│                                                              │
│  2. S-CURVE                                                  │
│     ┌────────────────────┐                                  │
│     │        ╱───        │ Slow start, fast middle,        │
│     │      ╱│            │ slow end                         │
│     │    ──╱             │ Smooth transitions               │
│     └────────────────────┘                                  │
│                                                              │
│  3. LINEAR                                                   │
│     ┌────────────────────┐                                  │
│     │         ╱          │ Straight line                    │
│     │       ╱            │ Constant rate of change          │
│     │     ╱              │ Simple volume adjustments        │
│     └────────────────────┘                                  │
│                                                              │
│  4. EXPONENTIAL                                              │
│     ┌────────────────────┐                                  │
│     │            ╱───    │ Slow start, rapid end           │
│     │          ╱         │ Natural-sounding fades           │
│     │    ────╱           │ Good for music fade-outs        │
│     └────────────────────┘                                  │
│                                                              │
│  5. LOGARITHMIC                                              │
│     ┌────────────────────┐                                  │
│     │      ───╲          │ Rapid start, slow end           │
│     │           ╲        │ Perceptually linear             │
│     │            ╲___    │ Matches human hearing           │
│     └────────────────────┘                                  │
│                                                              │
│  6. PRESET 1-5 (User Definable)                             │
│     ├── Store custom curve shapes                           │
│     ├── Cmd/Ctrl+click preset button to save               │
│     └── 5 presets per fade type (in/out/cross)             │
│                                                              │
│  Slope Options (Crossfades):                                 │
│  ├── EQUAL GAIN: Linear amplitude crossfade                │
│  │   └── Sum of levels = constant                          │
│  └── EQUAL POWER: Energy-preserving crossfade              │
│      └── Maintains perceived loudness                       │
│      └── Recommended for most material                      │
│                                                              │
│  Crossfade Placement:                                        │
│  ├── Centered: Equal parts on both clips                   │
│  ├── Pre-Splice: Fade before edit point                    │
│  └── Post-Splice: Fade after edit point                    │
│                                                              │
│  Keyboard Shortcuts (Commands Focus ON):                     │
│  ├── D: Create Fade In to cursor                           │
│  ├── G: Create Fade Out from cursor                        │
│  ├── F: Create Crossfade at selection                      │
│  └── Ctrl+F / Cmd+F: Open Fades dialog                     │
│                                                              │
│  Batch Fades:                                                │
│  ├── Select multiple clips → Edit > Fades > Create         │
│  ├── Apply same settings to all selected                   │
│  ├── Options per fade type:                                │
│  │   ├── Create new fades                                  │
│  │   ├── Create new fade-ins                               │
│  │   ├── Create new fade-outs                              │
│  │   └── Adjust existing fades                             │
│  └── Length in ms ili samples                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.5 Edit Modes

```
┌─────────────────────────────────────────────────────────────┐
│                      EDIT MODES                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. SHUFFLE MODE (F1)                                        │
│     ┌────────────────────────────────────────────────────┐  │
│     │ Before: [Clip A]    [Clip B]    [Clip C]          │  │
│     │                                                    │  │
│     │ Delete Clip B:                                     │  │
│     │ After:  [Clip A][Clip C]                          │  │
│     │         ← C automatically moves to fill gap        │  │
│     └────────────────────────────────────────────────────┘  │
│     Behavior:                                                │
│     ├── Clips butt against each other                       │
│     ├── Deleting clip shifts following clips earlier        │
│     ├── Inserting clip pushes following clips later         │
│     ├── No gaps allowed                                     │
│     └── Ideal for: Podcasts, dialogue editing               │
│                                                              │
│  2. SLIP MODE (F2)                                           │
│     ┌────────────────────────────────────────────────────┐  │
│     │ Complete freedom of clip placement                 │  │
│     │                                                    │  │
│     │ [Clip A]     [Clip B]          [Clip C]           │  │
│     │              ↑                                     │  │
│     │              Move anywhere, no snapping            │  │
│     └────────────────────────────────────────────────────┘  │
│     Behavior:                                                │
│     ├── No grid snapping                                    │
│     ├── Sample-accurate placement                           │
│     ├── Clips can overlap (later clip on top)               │
│     ├── Most flexible mode                                  │
│     └── Ideal for: General editing, fine adjustments        │
│                                                              │
│  3. SPOT MODE (F3)                                           │
│     ┌────────────────────────────────────────────────────┐  │
│     │ Click/drag clip → Dialog appears:                  │  │
│     │                                                    │  │
│     │  ┌──────────────────────────────────┐             │  │
│     │  │ Spot Dialog                       │             │  │
│     │  │ Time Scale: [Timecode ▼]         │             │  │
│     │  │ Start: [01:00:05:12]             │             │  │
│     │  │ Sync Point: [01:00:07:00]        │             │  │
│     │  │ End: [01:00:12:18]               │             │  │
│     │  └──────────────────────────────────┘             │  │
│     └────────────────────────────────────────────────────┘  │
│     Behavior:                                                │
│     ├── Precise timecode placement                          │
│     ├── Enter exact location value                          │
│     ├── Reference by Start, End, or Sync Point              │
│     └── Ideal for: Post-production, ADR, sound design       │
│                                                              │
│  4. GRID MODE (F4)                                           │
│     ┌────────────────────────────────────────────────────┐  │
│     │ Clips snap to grid lines                           │  │
│     │                                                    │  │
│     │ Grid: |    |    |    |    |    |    |             │  │
│     │       [Clip A   ][Clip B]    [Clip C]             │  │
│     │       ↑          ↑           ↑                     │  │
│     │       Snapped to grid                              │  │
│     └────────────────────────────────────────────────────┘  │
│                                                              │
│     SUB-MODES:                                               │
│                                                              │
│     a) ABSOLUTE GRID (F4 once)                              │
│        ├── Clips snap directly to nearest grid line        │
│        ├── Start point aligns exactly to grid              │
│        └── Ideal for: Tight, quantized arrangements        │
│                                                              │
│     b) RELATIVE GRID (F4 twice)                             │
│        ├── Maintains relative offset from grid             │
│        ├── Moves by grid increments                        │
│        ├── Original position preserved                     │
│        └── Ideal for: Moving while keeping timing feel     │
│                                                              │
│     Grid Values:                                             │
│     ├── Bars: 1 Bar, 2 Bars, 4 Bars, 8 Bars               │
│     ├── Beats: 1/1, 1/2, 1/4, 1/8, 1/16, 1/32, 1/64       │
│     ├── Dotted: 1/2., 1/4., 1/8., etc.                    │
│     ├── Triplet: 1/2t, 1/4t, 1/8t, etc.                   │
│     ├── Time: Seconds, Frames                              │
│     └── Follow Main Time Scale (adaptive)                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.6 Edit Tools

```
┌─────────────────────────────────────────────────────────────┐
│                      EDIT TOOLS                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. ZOOMER TOOL                                              │
│     ├── Click: Zoom in                                      │
│     ├── Opt/Alt+Click: Zoom out                            │
│     ├── Drag: Zoom to selection                            │
│     └── Shortcut: R (Commands Focus)                       │
│                                                              │
│  2. TRIM TOOL                                                │
│     ├── Standard: Adjust clip boundaries                   │
│     ├── Time Compression/Expansion (TCE):                   │
│     │   └── Stretch/shrink with Elastic Audio              │
│     ├── Loop: Repeat clip content                          │
│     └── Shortcut: E (Commands Focus)                       │
│                                                              │
│  3. SELECTOR TOOL                                            │
│     ├── Click: Place cursor                                │
│     ├── Click+Drag: Make selection                         │
│     ├── Double-click: Select entire clip                   │
│     ├── Triple-click: Select entire track                  │
│     └── Shortcut: W (Commands Focus)                       │
│                                                              │
│  4. GRABBER TOOL                                             │
│     ├── Object Grabber: Move/copy clips                    │
│     ├── Separation Grabber: Separate at click              │
│     ├── Time Grabber: Move clip in time only               │
│     └── Shortcut: G (Commands Focus)                       │
│                                                              │
│  5. SCRUBBER TOOL                                            │
│     ├── Drag across audio to audition                      │
│     ├── Jog/shuttle behavior                               │
│     └── Shortcut: H (Commands Focus)                       │
│                                                              │
│  6. PENCIL TOOL                                              │
│     ├── Free Hand: Draw arbitrary shapes                   │
│     ├── Line: Draw straight lines                          │
│     ├── Triangle: Create triangle wave                     │
│     ├── Square: Create square wave                         │
│     ├── Random: Create random values                       │
│     ├── Parabolic: Create curved shapes                    │
│     ├── S-Curve: Create S-shaped curves                    │
│     └── Shortcut: P (Commands Focus)                       │
│     Use for: Automation, MIDI velocity, audio repair       │
│                                                              │
│  7. SMART TOOL (Multiple Tool Combo)                         │
│     ┌────────────────────────────────────────────────────┐  │
│     │              SMART TOOL ZONES                       │  │
│     │  ┌──────────────────────────────────────────────┐  │  │
│     │  │  Fade Zone │    Selector Zone    │ Fade Zone │  │  │
│     │  │  (top)     │    (middle-top)     │ (top)     │  │  │
│     │  ├───────────────────────────────────────────────┤  │  │
│     │  │            │                      │           │  │  │
│     │  │   Trim     │    Object/Move       │   Trim    │  │  │
│     │  │   Zone     │    Zone              │   Zone    │  │  │
│     │  │  (edges)   │    (center)          │  (edges)  │  │  │
│     │  │            │                      │           │  │  │
│     │  ├───────────────────────────────────────────────┤  │  │
│     │  │            │    Grabber Zone      │           │  │  │
│     │  │            │    (bottom)          │           │  │  │
│     │  └──────────────────────────────────────────────┘  │  │
│     └────────────────────────────────────────────────────┘  │
│     Behavior:                                                │
│     ├── Top corners: Fade in/out                            │
│     ├── Top center: Selector                                │
│     ├── Left/Right edges: Trimmer                           │
│     ├── Center: Selector (top half), Grabber (bottom)       │
│     └── Enable: Click all 3 tool buttons simultaneously     │
│                                                              │
│  Tool Shortcuts:                                             │
│  ├── F5: Zoomer                                             │
│  ├── F6: Trim                                               │
│  ├── F7: Selector                                           │
│  ├── F8: Grabber                                            │
│  ├── F9: Scrubber                                           │
│  ├── F10: Pencil                                            │
│  └── Escape: Toggle between current and Zoomer              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.7 Playlists

```
┌─────────────────────────────────────────────────────────────┐
│                    PLAYLIST SYSTEM                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Svaki track ima multiple playlists                     │
│  ├── Samo jedan playlist je aktivan (svira)                 │
│  ├── Ostali čuvaju alternative takes                        │
│  └── Non-destructive — original data uvek sačuvan          │
│                                                              │
│  Playlist Types:                                             │
│                                                              │
│  1. AUDIO PLAYLISTS                                          │
│     ├── Store multiple takes od istog izvora               │
│     ├── Comping workflow                                    │
│     ├── A/B comparison                                      │
│     └── Version management                                  │
│                                                              │
│  2. MIDI PLAYLISTS (2024.10+)                                │
│     ├── NOVO — ranije nije postojalo                        │
│     ├── Ista funkcionalnost kao Audio Playlists            │
│     ├── Works on Instrument i MIDI tracks                   │
│     └── Comping MIDI performances                           │
│                                                              │
│  Playlist View:                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Main (Active): [████████████████████████████]          │ │
│  │ ──────────────────────────────────────────────         │ │
│  │ Take 1: [▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒]              │ │
│  │ Take 2: [▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒]              │ │
│  │ Take 3: [▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒]              │ │
│  │                                                         │ │
│  │ ► Speaker icon: Audition individual playlist           │ │
│  │ ★ Star icon: Mark best take                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Comping Workflow:                                           │
│  1. Record multiple takes (Loop Record or manual)           │
│  2. Enable Playlist View on track                           │
│  3. Create new blank playlist as Target                     │
│  4. Select portions from each take                          │
│  5. Selections appear on Target playlist                    │
│  6. Pro Tools creates crossfades automatically              │
│                                                              │
│  Recording Options:                                          │
│  ├── Automatically Create New Playlists When Loop Recording │
│  │   └── Each pass = new playlist                          │
│  ├── Target Playlist: Destination for comps                │
│  └── Audition button: Listen without making active          │
│                                                              │
│  Shortcuts:                                                   │
│  ├── Ctrl+\ : New Playlist                                  │
│  ├── Ctrl+Cmd+\ : Duplicate Playlist                        │
│  ├── Opt+Cmd+Shift+↑/↓ : Cycle selection through playlists │
│  └── Click track name → Playlists submenu                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.8 Memory Locations & Markers

```
┌─────────────────────────────────────────────────────────────┐
│                  MEMORY LOCATIONS SYSTEM                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Kapacitet: 999 Memory Locations per session                │
│                                                              │
│  Memory Location Types:                                      │
│                                                              │
│  1. MARKER                                                   │
│     ├── Point on timeline                                   │
│     ├── Displays in Marker Ruler                            │
│     ├── Click to jump to location                           │
│     └── Ideal za: Song sections, cue points                 │
│                                                              │
│  2. SELECTION                                                │
│     ├── Stores timeline selection (start + end)             │
│     ├── Recalls both in/out points                          │
│     ├── Can include track selection                         │
│     └── Ideal za: Loop regions, edit areas                  │
│                                                              │
│  3. NONE                                                     │
│     ├── Stores other properties only                        │
│     ├── No timeline position                                │
│     └── Ideal za: View recalls, window configs              │
│                                                              │
│  General Properties (All Types):                             │
│  ├── Zoom Settings                                          │
│  │   └── Horizontal, Audio, MIDI zoom levels               │
│  ├── Pre/Post Roll Times                                    │
│  ├── Track Show/Hide                                        │
│  │   └── Which tracks are visible                          │
│  ├── Track Heights                                          │
│  │   └── Size of each track                                │
│  ├── Group Enables                                          │
│  │   └── Which groups are active                           │
│  └── Window Configuration                                   │
│      └── Recall specific window layout                      │
│                                                              │
│  Window Configurations:                                      │
│  ├── Up to 99 configurations                                │
│  ├── Store: Window positions, sizes, visibility             │
│  ├── Include: Edit, Mix, MIDI Editor, etc.                  │
│  ├── Edit Window layout (clip list, rulers)                 │
│  └── Create: Window → Configurations → New                  │
│                                                              │
│  Create Memory Location:                                     │
│  ├── Enter key (numpad): At cursor/selection               │
│  ├── Cmd+Enter: Open Memory Location dialog                │
│  └── Click + in Memory Locations window                     │
│                                                              │
│  Recall Memory Location:                                     │
│  ├── Click marker in Ruler                                  │
│  ├── Period (.) + Number + Period (.) on numpad            │
│  ├── Period (.) + Number + Asterisk (*) for Window Config  │
│  └── Memory Locations window: double-click                  │
│                                                              │
│  Memory Locations Window Features:                           │
│  ├── Filter by type (Marker, Selection, None)               │
│  ├── Filter by Marker Track                                 │
│  ├── Filter by color                                        │
│  ├── Filter by text search                                  │
│  ├── Sort options                                           │
│  └── Edit/Delete multiple                                   │
│                                                              │
│  Shortcuts:                                                   │
│  ├── Period + Number + Period: Jump to marker              │
│  ├── Period + Period: Previous marker                      │
│  ├── Next Marker: Ctrl+. (period)                          │
│  └── Previous Marker: Ctrl+, (comma)                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. EDITING CAPABILITIES

### 5.1 Elastic Audio (Detailed)

```
┌─────────────────────────────────────────────────────────────┐
│                 ELASTIC AUDIO DEEP DIVE                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Kako funkcioniše:                                           │
│                                                              │
│  1. ANALYSIS PHASE                                           │
│     ├── Audio je analiziran za transients                   │
│     ├── Warp markers su generisani automatski               │
│     ├── Event Sensitivity kontroliše detekciju              │
│     └── Može se raditi offline ili real-time                │
│                                                              │
│  2. PROCESSING PHASE                                         │
│     ├── Time stretching/compression                         │
│     ├── Pitch shifting (optional)                           │
│     └── Preserves transients based on algorithm             │
│                                                              │
│  Elastic Audio Processing Modes:                             │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Mode          │ Description                         │    │
│  ├───────────────┼─────────────────────────────────────┤    │
│  │ Real-Time     │ Processes during playback           │    │
│  │               │ CPU intensive                       │    │
│  │               │ Instant feedback                    │    │
│  ├───────────────┼─────────────────────────────────────┤    │
│  │ Rendered      │ Pre-calculates audio                │    │
│  │               │ Zero playback CPU                   │    │
│  │               │ Creates rendered files              │    │
│  │               │ Toggle: Track > Elastic Audio >    │    │
│  │               │ Rendered Processing                 │    │
│  └───────────────┴─────────────────────────────────────┘    │
│                                                              │
│  Warp Markers:                                               │
│  ├── Automatically detected transients                      │
│  ├── Can be manually added/removed                          │
│  ├── Drag to adjust timing                                  │
│  ├── Types:                                                 │
│  │   ├── Event Marker (movable)                            │
│  │   ├── Warp Marker (anchored reference)                  │
│  │   └── Tempo Event (follows tempo map)                   │
│  └── Telescoping: Adjacent regions stretch/shrink          │
│                                                              │
│  Elastic Properties Window:                                  │
│  ├── Event Sensitivity: Detection threshold                │
│  ├── Input Gain: Pre-process gain                          │
│  ├── Pitch Shift: Semitones (-36 to +36)                   │
│  ├── Pitch Shift: Cents (-50 to +50)                       │
│  ├── TCE (Time Compression/Expansion): Ratio               │
│  ├── Formant Shift: Preserve/shift formants                │
│  └── Follow Tempo: Track follows session tempo              │
│                                                              │
│  Quantize with Elastic Audio:                                │
│  1. Apply Elastic Audio to track                            │
│  2. Event > Event Operations > Quantize                     │
│  3. Set grid resolution                                     │
│  4. Apply — audio conforms to grid                          │
│                                                              │
│  Algorithm Comparison:                                        │
│  ┌─────────────┬──────────────┬────────────┬───────────┐   │
│  │ Algorithm   │ Best For     │ Artifacts  │ CPU       │   │
│  ├─────────────┼──────────────┼────────────┼───────────┤   │
│  │ Polyphonic  │ Full mixes   │ Low        │ High      │   │
│  │ Rhythmic    │ Drums        │ Very Low   │ Medium    │   │
│  │ Monophonic  │ Vocals/Bass  │ Medium     │ Medium    │   │
│  │ Varispeed   │ Effects      │ None*      │ Low       │   │
│  │ X-Form      │ Critical     │ Lowest     │ Offline   │   │
│  │ Elastique   │ All (2023.3+)│ Very Low   │ Med-High  │   │
│  └─────────────┴──────────────┴────────────┴───────────┘   │
│  * Varispeed links pitch/time — not technically artifact    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 AudioSuite Processing

```
┌─────────────────────────────────────────────────────────────┐
│                  AUDIOSUITE PROCESSING                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Offline (non-real-time) processing                     │
│  ├── Renders effect permanently to new file                 │
│  ├── Non-destructive (original preserved)                   │
│  └── Reduces CPU load (no real-time processing)             │
│                                                              │
│  AudioSuite Menu: AudioSuite > [Category] > [Plugin]        │
│                                                              │
│  Processing Modes:                                           │
│  ├── CLIP BY CLIP: Process each clip independently         │
│  ├── ENTIRE SELECTION: Process selection as one            │
│  └── CREATE CONTINUOUS FILE: Merge all into one file       │
│                                                              │
│  Handle Options:                                             │
│  ├── USE IN PLAYLIST: Process visible portion only         │
│  ├── Add X seconds handles: Process extra before/after     │
│  └── RENDER ENTIRE FILE: Process full source file          │
│                                                              │
│  Recommended Handle Length: 2-5 seconds                     │
│  └── Allows extending clip later without re-processing      │
│                                                              │
│  AudioSuite-Only Effects (not available real-time):          │
│  ├── Reverse: Backwards playback                           │
│  ├── Vari-Fi: Tape speed up/down effect                    │
│  ├── Time Shift: Pitch/time manipulation                   │
│  ├── Gain: Static gain adjustment                          │
│  ├── Normalize: Peak/RMS normalization                     │
│  ├── DC Offset Removal: Center waveform                    │
│  ├── Signal Generator: Create test tones                   │
│  └── Invert: Phase invert                                  │
│                                                              │
│  Workflow Example — Batch Normalize:                         │
│  1. Select multiple clips                                   │
│  2. AudioSuite > Other > Normalize                          │
│  3. Set target level (e.g., -0.3dB peak)                   │
│  4. Click Analyze (checks all clips)                        │
│  5. Click Render (processes all)                            │
│                                                              │
│  Tips:                                                        │
│  ├── Extend selection beyond clip for reverb tails          │
│  ├── Use "Create Continuous File" for stems                 │
│  ├── Multiple AudioSuite windows can be open (PT10+)        │
│  ├── Save AudioSuite chains as presets                      │
│  └── Window Configurations can include AudioSuite           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Beat Detective

```
┌─────────────────────────────────────────────────────────────┐
│                     BEAT DETECTIVE                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: Event > Beat Detective (Cmd+8 / Ctrl+8)            │
│                                                              │
│  Operation Modes:                                            │
│                                                              │
│  1. BAR|BEAT MARKER GENERATION                               │
│     ├── Creates tempo map from audio                        │
│     ├── Analyzes transients                                 │
│     ├── Generates Bar/Beat markers                          │
│     └── Session follows audio tempo                         │
│                                                              │
│     Workflow:                                                │
│     a) Select audio region                                  │
│     b) Set time signature and start bar                     │
│     c) Click "Analyze"                                      │
│     d) Adjust Sensitivity                                   │
│     e) Click "Generate"                                     │
│                                                              │
│  2. GROOVE TEMPLATE EXTRACTION                               │
│     ├── Captures timing feel from performance               │
│     ├── Saves as groove template                            │
│     ├── Apply to other tracks via Quantize                  │
│     └── Includes timing AND dynamics                        │
│                                                              │
│  3. CLIP SEPARATION                                          │
│     ├── Cuts audio at transients                            │
│     ├── Creates individual clips per hit                    │
│     └── Prepares for Clip Conform                           │
│                                                              │
│  4. CLIP CONFORM                                             │
│     ├── Moves separated clips to grid                       │
│     ├── Strength: How strictly to grid (0-100%)             │
│     ├── Swing: Add shuffle feel                             │
│     └── Works with Edit Smoothing for crossfades            │
│                                                              │
│  5. EDIT SMOOTHING                                           │
│     ├── Creates crossfades at edit points                   │
│     ├── Fill gaps option                                    │
│     └── Auto-fills silence between clips                    │
│                                                              │
│  Detection Settings:                                         │
│  ├── ANALYSIS TYPE:                                         │
│  │   ├── High Emphasis: Cymbals, overheads                 │
│  │   ├── Low Emphasis: Kick, toms                          │
│  │   └── Enhanced Resolution: All-purpose                  │
│  ├── SENSITIVITY: Transient detection threshold            │
│  ├── TRIGGER PAD: Cut point offset (ms before trigger)     │
│  └── RESOLUTION: Beat subdivision for analysis             │
│                                                              │
│  Best Practices:                                             │
│  ├── Work in small sections (8-16 bars)                    │
│  ├── Verify each section before moving on                  │
│  ├── Use different Analysis types per track                │
│  │   └── Kick = Low Emphasis, Hats = High Emphasis         │
│  ├── Group related tracks (drums) for batch processing     │
│  └── Always listen — don't blindly trust visual            │
│                                                              │
│  Ideal Material:                                             │
│  ├── Clear transients (drums, percussion)                  │
│  ├── Consistent tempo (not rubato)                         │
│  └── Good signal-to-noise                                  │
│                                                              │
│  Problematic Material:                                       │
│  ├── Legato phrases                                        │
│  ├── Soft attacks                                          │
│  ├── Widely varying tempos                                 │
│  └── Noisy recordings                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 Strip Silence

```
┌─────────────────────────────────────────────────────────────┐
│                     STRIP SILENCE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: Edit > Strip Silence (Cmd+U / Ctrl+U)              │
│                                                              │
│  Funkcija:                                                   │
│  ├── Analyzes audio for quiet sections                      │
│  ├── Separates or removes audio below threshold             │
│  └── Non-destructive editing                                │
│                                                              │
│  Parameters:                                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ STRIP THRESHOLD                                         │ │
│  │ └── Level below which audio is "silence"               │ │
│  │     Range: -96dB to 0dB                                │ │
│  │                                                         │ │
│  │ MINIMUM STRIP DURATION                                  │ │
│  │ └── Shortest silence worth removing                    │ │
│  │     Range: 0ms to several seconds                      │ │
│  │     Prevents micro-edits on short gaps                 │ │
│  │                                                         │ │
│  │ CLIP START PAD                                          │ │
│  │ └── Extra time before detected audio                   │ │
│  │     Preserves attack transients                        │ │
│  │                                                         │ │
│  │ CLIP END PAD                                            │ │
│  │ └── Extra time after detected audio                    │ │
│  │     Preserves decay/reverb tails                       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Actions:                                                     │
│  ├── STRIP: Remove silence, keeping audio clips            │
│  ├── SEPARATE: Create edits but keep all material          │
│  ├── EXTRACT: Remove audio, keep only silence              │
│  └── RENAME: Rename resulting clips with suffix/numbering  │
│                                                              │
│  Common Uses:                                                │
│  ├── Cleaning tom tracks (remove cymbal bleed)             │
│  ├── Dialogue editing (remove silence between lines)        │
│  ├── Creating separate clips from long takes               │
│  ├── Preparing audio for drum replacement                  │
│  └── Vocal cleanup (remove breaths, silences)              │
│                                                              │
│  Workflow Example — Tom Cleanup:                             │
│  1. Select tom track                                        │
│  2. Open Strip Silence                                      │
│  3. Set threshold just above noise floor                   │
│  4. Set minimum duration to avoid catching bleed           │
│  5. Set pads (20-50ms typical)                             │
│  6. Preview (visual shows what will be kept)               │
│  7. Click Strip                                            │
│  8. Optional: Batch Fades for smooth transitions           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.5 Sound Replacer

```
┌─────────────────────────────────────────────────────────────┐
│                    SOUND REPLACER                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Type: AudioSuite Plugin (OFFLINE only)                     │
│  Access: AudioSuite > Other > Sound Replacer                │
│                                                              │
│  Svrha:                                                      │
│  ├── Replace drum hits with samples                         │
│  ├── Layer samples over original                            │
│  ├── Dynamics-sensitive replacement                         │
│  └── Post-production drum augmentation                      │
│                                                              │
│  Sample Slots (3):                                           │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ SAMPLE 1: SOFT HITS                                     │ │
│  │ └── Triggered by: Low velocity transients              │ │
│  │                                                         │ │
│  │ SAMPLE 2: MEDIUM HITS                                   │ │
│  │ └── Triggered by: Medium velocity transients           │ │
│  │                                                         │ │
│  │ SAMPLE 3: HARD HITS                                     │ │
│  │ └── Triggered by: High velocity transients             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Threshold Settings:                                         │
│  ├── Threshold 1→2: Level dividing soft/medium             │
│  └── Threshold 2→3: Level dividing medium/hard             │
│                                                              │
│  Key Features:                                               │
│  ├── PEAK ALIGN: Sync sample peak to source peak           │
│  │   └── More accurate transient alignment                 │
│  ├── CROSSFADE: Smooth transitions between zones           │
│  │   └── Avoids abrupt jumps between samples               │
│  ├── DYNAMICS: Preserve original dynamics                  │
│  │   └── Scale sample level to match source                │
│  └── MIX: Blend replacement with original                  │
│                                                              │
│  Limitations:                                                │
│  ├── Offline only — cannot monitor in real-time            │
│  ├── No intelligent bleed rejection                        │
│  │   └── May trigger on cymbal bleed                       │
│  ├── Pre-editing often required                            │
│  │   └── Use Strip Silence first                           │
│  └── One track at a time                                   │
│                                                              │
│  Workflow:                                                   │
│  1. Clean source track (Strip Silence)                      │
│  2. Load 1-3 samples in Sound Replacer                      │
│  3. Set thresholds to match performance dynamics           │
│  4. Enable Peak Align for tight timing                     │
│  5. Enable Crossfade for smooth transitions                │
│  6. Set Mix for blend (100% = full replacement)            │
│  7. Click Render                                           │
│                                                              │
│  Alternative Real-Time Solutions:                            │
│  ├── Steven Slate Trigger 2                                │
│  ├── Drumagog                                              │
│  ├── SPL DrumXchanger                                      │
│  └── Massey DRT                                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

*Dokument se nastavlja u Part 3...*
# Pro Tools 2024 — Ultra-Detaljna Tehnička Analiza (Part 3)

---

## 6. MIDI CAPABILITIES

### 6.1 MIDI Editor

```
┌─────────────────────────────────────────────────────────────┐
│                      MIDI EDITOR                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access:                                                     │
│  ├── Double-click MIDI clip with Grabber                   │
│  ├── Window > MIDI Editor                                  │
│  └── Shortcut: Ctrl+= (Win) / Cmd+= (Mac)                  │
│                                                              │
│  Layout:                                                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    TOOLBAR                              │ │
│  │  [Tools] [Grid] [Quantize] [Mirrored MIDI]             │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │                                                         │ │
│  │  ┌──────┐  PIANO ROLL                                  │ │
│  │  │ C5   │  ████████████  ████                         │ │
│  │  │ B4   │        ██████████                            │ │
│  │  │ A4   │  ██████      ████████████                   │ │
│  │  │ G4   │                    ████████                  │ │
│  │  │ F4   │  ████  ████████████                         │ │
│  │  │ ...  │                                              │ │
│  │  └──────┘                                              │ │
│  │   Piano                                                 │ │
│  │   Keys                                                  │ │
│  │                                                         │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │  AUTOMATION LANES                                       │ │
│  │  [Velocity] ▂▃▅▆▇▇▅▃▂▃▅▇▆▅▃                           │ │
│  │  [CC1 Mod]  ────────╱╲─────────                       │ │
│  │  [Pitch]    ───────────────────                       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Editing Features:                                           │
│  ├── Note creation: Pencil tool                            │
│  ├── Note selection: Grabber tool                          │
│  ├── Note duration: Trim tool                              │
│  ├── Velocity editing: In automation lane                  │
│  ├── Multi-track editing: See notes from multiple tracks   │
│  ├── Note snapping: To grid or other notes                 │
│  ├── Ctrl/Cmd+hover: Snap note start to cursor            │
│  └── Scrub button: Audition MIDI data by scrubbing        │
│                                                              │
│  Display Options:                                            │
│  ├── Notation View: Traditional note view                  │
│  ├── Piano Roll View: Standard DAW view                    │
│  ├── Velocity View: Color-coded by velocity                │
│  ├── Duration View: Show note lengths graphically          │
│  └── Superimposed Tracks: See multiple tracks              │
│                                                              │
│  MIDI Operations Tab (NOVO):                                 │
│  ├── Previously in Event menu                               │
│  ├── Now integrated in MIDI Editor                          │
│  └── Quick access to quantize, transpose, etc.              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 MIDI Event List

```
┌─────────────────────────────────────────────────────────────┐
│                    MIDI EVENT LIST                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: Window > MIDI Event List (Opt+= / Alt+=)           │
│                                                              │
│  Funkcija:                                                   │
│  ├── Tabular view of all MIDI data                          │
│  ├── Precise numerical editing                              │
│  ├── Find specific events                                   │
│  └── Batch edit by selection                                │
│                                                              │
│  Columns:                                                     │
│  ┌──────────┬──────────┬───────┬──────┬────────┬─────────┐ │
│  │ Location │ Event    │ Pitch │ Vel  │ Length │ Channel │ │
│  ├──────────┼──────────┼───────┼──────┼────────┼─────────┤ │
│  │ 1|1|000  │ Note On  │ C4    │ 100  │ 0|1|0  │ 1       │ │
│  │ 1|2|000  │ Note On  │ E4    │ 87   │ 0|0|480│ 1       │ │
│  │ 1|2|240  │ CC       │ 1     │ 64   │ -      │ 1       │ │
│  │ 1|3|000  │ Note On  │ G4    │ 92   │ 0|2|0  │ 1       │ │
│  │ ...      │ ...      │ ...   │ ...  │ ...    │ ...     │ │
│  └──────────┴──────────┴───────┴──────┴────────┴─────────┘ │
│                                                              │
│  Event Types Displayed:                                      │
│  ├── Note On/Off                                            │
│  ├── Control Change (CC)                                    │
│  ├── Program Change                                         │
│  ├── Pitch Bend                                             │
│  ├── Aftertouch (Channel/Poly)                              │
│  ├── System Exclusive (SysEx)                               │
│  └── Tempo/Meter changes                                    │
│                                                              │
│  Editing:                                                     │
│  ├── Click cell to edit value                               │
│  ├── Tab to move between cells                              │
│  ├── Delete key to remove events                            │
│  ├── Insert key to add events                               │
│  └── Double-click to hear note                              │
│                                                              │
│  Filter Options:                                             │
│  ├── Show/hide event types                                  │
│  ├── Filter by channel                                      │
│  └── Filter by selection/time range                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.3 Score Editor

```
┌─────────────────────────────────────────────────────────────┐
│                     SCORE EDITOR                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: Window > Score Editor (Ctrl+Opt+= / Ctrl+Alt+=)    │
│                                                              │
│  Poreklo: Koristi Sibelius scoring algoritme                │
│                                                              │
│  Funkcionalnost:                                             │
│  ├── Traditional music notation view                        │
│  ├── Read MIDI as standard notation                         │
│  ├── Basic score printing                                   │
│  └── Note entry via notation                                │
│                                                              │
│  Display Elements:                                           │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  𝄞  Time Signature: 4/4                                │ │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    │ │
│  │     ♩  ♪ ♪  ♩    |   ♩.  ♫   ♩   |  𝄐  ♩  ♩  ♩    │ │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    │ │
│  │  𝄢  Key Signature: C Major                             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Notation Settings:                                          │
│  ├── Quantize display (separate from playback)             │
│  ├── Note spelling (sharps vs flats)                       │
│  ├── Stem direction                                        │
│  ├── Beam grouping                                         │
│  └── Clef selection                                        │
│                                                              │
│  Limitations vs Full Notation Software:                      │
│  ├── No advanced engraving                                 │
│  ├── Limited layout control                                │
│  ├── No lyrics                                             │
│  ├── Basic articulations only                              │
│  └── Not for publication-ready scores                       │
│                                                              │
│  Preporučeno za:                                             │
│  ├── Quick reference while editing MIDI                     │
│  ├── Musicians who read notation                            │
│  └── Lead sheet creation                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.4 MIDI Operations

```
┌─────────────────────────────────────────────────────────────┐
│                   MIDI OPERATIONS                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: Event > MIDI Operations > [Operation]              │
│  Alt Access: MIDI Editor > Operations Tab                   │
│                                                              │
│  Event Operations Window: Alt+3 (numpad)                    │
│                                                              │
│  1. QUANTIZE                                                 │
│     ├── Grid: 1/4, 1/8, 1/16, 1/32, etc.                   │
│     ├── Tuplets: 1/8T, 1/16T, etc.                         │
│     ├── Strength: 0-100% (how strictly to grid)            │
│     ├── Swing: Add shuffle feel (0-100%)                   │
│     ├── Include within: Range around grid line             │
│     ├── Exclude within: Don't move if already close        │
│     ├── Randomize: Add human feel                          │
│     └── Options: Note On, Note Off, Preserve duration      │
│                                                              │
│  2. CHANGE VELOCITY                                          │
│     ├── Set to: Fixed value (1-127)                        │
│     ├── Add: Add/subtract amount                           │
│     ├── Scale: Percentage (50-200%)                        │
│     ├── Smoothing: Apply to selected range                 │
│     └── Curve: Create velocity curve over selection        │
│                                                              │
│  3. CHANGE DURATION                                          │
│     ├── Set to: Fixed length                               │
│     ├── Add: Add/subtract time                             │
│     ├── Scale: Percentage                                  │
│     ├── Legato: Extend to next note                        │
│     └── Remove Overlap: Fix overlapping notes              │
│                                                              │
│  4. TRANSPOSE                                                │
│     ├── Semitones: -127 to +127                            │
│     ├── Octaves: Quick octave shifts                       │
│     └── Key Signature aware: Stay in key                   │
│                                                              │
│  5. SELECT/SPLIT NOTES                                       │
│     ├── By pitch range                                     │
│     ├── By velocity range                                  │
│     ├── By position                                        │
│     └── Split to separate tracks                           │
│                                                              │
│  6. INPUT QUANTIZE (Real-Time)                               │
│     ├── Quantize notes AS you record                       │
│     ├── Apply grid to input                                │
│     └── Setup: Setup > MIDI > Input Quantize               │
│                                                              │
│  7. RESTORE PERFORMANCE                                      │
│     ├── Undo quantize                                      │
│     ├── Return to original timing                          │
│     └── Uses stored "original" timestamp                   │
│                                                              │
│  8. FLATTEN PERFORMANCE                                      │
│     ├── Make current timing the "original"                 │
│     ├── After this, Restore returns to current             │
│     └── Useful after intentional timing changes            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.5 Groove Templates

```
┌─────────────────────────────────────────────────────────────┐
│                   GROOVE TEMPLATES                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Capture "feel" of a performance                        │
│  ├── Apply that feel to other material                      │
│  └── Includes timing AND dynamics                           │
│                                                              │
│  Extraction:                                                  │
│  1. Beat Detective > Groove Template Extraction             │
│  2. Analyze audio with clear transients                     │
│  3. Define resolution (1/8, 1/16, etc.)                     │
│  4. Extract → Saves to Groove Clipboard                     │
│  5. Save as file: Event > Identify Beat > Save Groove       │
│                                                              │
│  Application:                                                 │
│  1. Select MIDI data to groove                              │
│  2. Event > MIDI Operations > Quantize                      │
│  3. Click Groove dropdown                                   │
│  4. Select groove template                                  │
│  5. Adjust Timing % and Velocity % strength                 │
│  6. Apply                                                   │
│                                                              │
│  Built-in Grooves (DigiGrooves):                            │
│  ├── Location: /Library/Application Support/Avid/          │
│  │             Pro Tools/Grooves/                           │
│  ├── Styles: Funk, Jazz, Rock, R&B, Hip-Hop               │
│  └── Machines: MPC, 808, 909, etc.                         │
│                                                              │
│  Groove Properties:                                          │
│  ├── PRE: How early/late notes fall before beat            │
│  ├── POST: How early/late notes fall after beat            │
│  ├── VELOCITY: Dynamics pattern                            │
│  └── DURATION: Note length variations                      │
│                                                              │
│  Custom Groove Creation:                                     │
│  ├── From MIDI: MIDI Operations > Quantize > Groove >      │
│  │              Extract From Selection                     │
│  ├── From Audio: Beat Detective extraction                 │
│  └── Save: Event > Identify Beat > Save Groove Template    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.6 Real-Time MIDI Properties

```
┌─────────────────────────────────────────────────────────────┐
│               REAL-TIME MIDI PROPERTIES                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Non-destructive MIDI transformations                   │
│  ├── Apply during playback                                  │
│  ├── Original data unchanged                                │
│  └── Can be committed (made permanent)                      │
│                                                              │
│  Access: Window > MIDI Controls (Cmd+Shift+0)               │
│          or Track > Real-Time Properties                    │
│                                                              │
│  Properties:                                                  │
│                                                              │
│  1. QUANTIZE                                                 │
│     ├── Real-time quantization                             │
│     ├── Same options as MIDI Operations                    │
│     └── Non-destructive                                    │
│                                                              │
│  2. TRANSPOSE                                                │
│     ├── Semitone offset: -127 to +127                      │
│     └── Applied during playback                            │
│                                                              │
│  3. VELOCITY                                                 │
│     ├── Offset: -127 to +127                               │
│     ├── Applied to all notes                               │
│     └── Stacks with existing velocities                    │
│                                                              │
│  4. DURATION                                                 │
│     ├── Percentage: 50% to 200%                            │
│     └── Scales note lengths                                │
│                                                              │
│  5. DELAY                                                    │
│     ├── Milliseconds: -1000 to +1000                       │
│     ├── Positive = plays later                             │
│     ├── Negative = plays earlier                           │
│     └── Useful for: Laying back, pushing ahead             │
│                                                              │
│  Commit Real-Time Properties:                                │
│  ├── Track > MIDI Real-Time Properties > Write to Clip     │
│  └── Makes transformations permanent                        │
│                                                              │
│  MIDI Delay Compensation (2024.10):                          │
│  ├── NEW: Automatic compensation for instrument latency    │
│  ├── Configure per track                                   │
│  └── Keeps MIDI in sync with audio                         │
│                                                              │
│  Input Monitoring (2024.10):                                 │
│  ├── NEW: Input monitor button on Instrument/MIDI tracks   │
│  ├── Hear input without arming record                      │
│  └── Matches Audio Track behavior                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. PLUGIN HOSTING

### 7.1 AAX Native

```
┌─────────────────────────────────────────────────────────────┐
│                      AAX NATIVE                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Format: Avid Audio eXtension (Native)                      │
│  Introduced: Pro Tools 10                                   │
│  Replaced: RTAS (Real-Time AudioSuite)                      │
│                                                              │
│  Specifikacije:                                              │
│  ├── Processing: Host CPU                                   │
│  ├── Bit depth: 32-bit ili 64-bit floating point           │
│  ├── Sample rates: Up to 192kHz                            │
│  ├── Latency: Reports to DAW for ADC                       │
│  └── Memory: Uses system RAM                               │
│                                                              │
│  Prednosti:                                                  │
│  ├── Scalable (more CPU = more plugins)                    │
│  ├── No dedicated DSP hardware required                    │
│  ├── All modern plugins available                          │
│  ├── Same sound as DSP version                             │
│  └── Works on all Pro Tools tiers                          │
│                                                              │
│  Ograničenja:                                                │
│  ├── Variable latency (buffer-dependent)                   │
│  ├── CPU spikes can cause audio dropouts                   │
│  ├── Limited by host computer power                        │
│  └── Latency higher than AAX DSP                           │
│                                                              │
│  Plugin Locations:                                           │
│  ├── macOS: /Library/Application Support/Avid/             │
│  │          Audio/Plug-Ins/                                │
│  ├── Windows: C:\Program Files\Common Files\               │
│  │            Avid\Audio\Plug-Ins\                         │
│  └── User presets: ~/Documents/Pro Tools/                  │
│                     Plug-In Settings/                       │
│                                                              │
│  Compatibility:                                              │
│  ├── Pro Tools 10+ (AAX Native)                            │
│  ├── Pro Tools First (limited selection)                   │
│  ├── Pro Tools Intro (limited selection)                   │
│  ├── Pro Tools Artist (full AAX Native)                    │
│  ├── Pro Tools Studio (full AAX Native)                    │
│  └── Pro Tools Ultimate (full AAX Native)                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 AAX DSP

```
┌─────────────────────────────────────────────────────────────┐
│                       AAX DSP                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Format: Avid Audio eXtension (DSP)                         │
│  Requirements: HDX hardware ili Carbon interface            │
│  Replaced: TDM (Time Division Multiplexing)                 │
│                                                              │
│  Specifikacije:                                              │
│  ├── Processing: Dedicated TI DSP chips                    │
│  ├── Bit depth: 32-bit floating point                      │
│  ├── Mix bus: 64-bit floating point                        │
│  ├── Latency: Fixed, ultra-low (0.7ms @ 96kHz)             │
│  └── Memory: Dedicated to DSP chips                        │
│                                                              │
│  Prednosti:                                                  │
│  ├── Deterministic latency (consistent)                    │
│  ├── No CPU load on host                                   │
│  ├── Stable — doesn't depend on OS/CPU                     │
│  ├── Zero-latency monitoring through plugins               │
│  └── Industry standard for tracking                        │
│                                                              │
│  Ograničenja:                                                │
│  ├── Fixed DSP resource per card                           │
│  ├── Plugin must support AAX DSP                           │
│  ├── Not all plugins available in DSP format               │
│  ├── Expensive hardware required                           │
│  └── 32-bit only (vs 64-bit Native option)                 │
│                                                              │
│  DSP Allocation:                                             │
│  ├── Each plugin uses specific DSP %                       │
│  ├── View in System Usage window                           │
│  ├── Different plugins = different DSP cost                │
│  └── Can run out of DSP before CPU                         │
│                                                              │
│  Mixed DSP + Native:                                         │
│  ├── Hybrid Engine allows mixing                           │
│  ├── Per-track DSP/Native switching                        │
│  ├── Native plugin after DSP costs voices                  │
│  └── Requires careful resource management                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 AudioSuite (Plugin Type)

```
┌─────────────────────────────────────────────────────────────┐
│                 AUDIOSUITE PLUGINS                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Tip: Offline processing plugins                            │
│  Purpose: Non-real-time audio processing                    │
│                                                              │
│  Razlika od Real-Time:                                       │
│  ┌────────────────────┬────────────────────────┐            │
│  │ AudioSuite         │ AAX Native/DSP         │            │
│  ├────────────────────┼────────────────────────┤            │
│  │ Offline render     │ Real-time processing   │            │
│  │ Creates new file   │ No new file            │            │
│  │ Zero playback CPU  │ Uses CPU/DSP           │            │
│  │ One-time process   │ Adjustable during      │            │
│  │                    │ playback               │            │
│  │ Permanent*         │ Fully reversible       │            │
│  └────────────────────┴────────────────────────┘            │
│  * Original file preserved, new file created                │
│                                                              │
│  Kada koristiti AudioSuite:                                  │
│  ├── CPU conservation (render heavy plugins)               │
│  ├── Processes not possible in real-time                   │
│  │   └── Reverse, Vari-Fi, Time Shift                      │
│  ├── Sending files to others (embedded processing)         │
│  ├── Archiving (baked-in effects)                          │
│  └── Noise reduction (iZotope RX)                          │
│                                                              │
│  AudioSuite Plugin Categories:                               │
│  ├── EQ                                                    │
│  ├── Dynamics                                              │
│  ├── Reverb                                                │
│  ├── Delay                                                 │
│  ├── Pitch Shift                                           │
│  ├── Time Shift                                            │
│  ├── Noise Reduction                                       │
│  └── Other (Normalize, Reverse, etc.)                      │
│                                                              │
│  Important: Ne svi real-time plugins imaju AudioSuite       │
│             verziju. Proverite plugin menu.                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 7.4 Instrument Tracks & Plugin Hosting

```
┌─────────────────────────────────────────────────────────────┐
│            INSTRUMENT TRACKS & VI HOSTING                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Instrument Track Signal Flow:                               │
│                                                              │
│  MIDI Input → [Virtual Instrument] → Audio Processing       │
│               ↑                      ↓                       │
│            Plugin Slot           Inserts F-J                │
│                                      ↓                       │
│                                   Output                     │
│                                                              │
│  Virtual Instrument Insert:                                  │
│  ├── Single instrument slot per track                       │
│  ├── Pre-insert position                                    │
│  ├── Receives all MIDI from track                          │
│  └── Outputs audio to track chain                          │
│                                                              │
│  Multi-Output Instruments:                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Kontakt / Battery / Superior Drummer etc.              │ │
│  │                                                         │ │
│  │ Setup:                                                  │ │
│  │ 1. Insert instrument on Instrument Track               │ │
│  │ 2. Configure internal outputs in plugin                │ │
│  │ 3. Create Auxiliary Inputs for each output             │ │
│  │ 4. Set Aux inputs to instrument outputs                │ │
│  │                                                         │ │
│  │ Example (Kontakt 8):                                    │ │
│  │ ├── Inst Track: Main stereo out                        │ │
│  │ ├── Aux 1: Kt. St. 3/4 (Drums bus)                    │ │
│  │ ├── Aux 2: Kt. St. 5/6 (Bass bus)                     │ │
│  │ └── Aux 3: Kt. St. 7/8 (Synth bus)                    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Kontakt 8 Integration (2024.10):                            │
│  ├── Bundled with all Pro Tools tiers                      │
│  ├── Kontakt 8 Player included                             │
│  ├── Pro Tools Factory Essentials Library                  │
│  └── Full Kontakt 8 features                               │
│                                                              │
│  MIDI Multi-Timbral Setup:                                   │
│  ├── Alternative to multi-output                           │
│  ├── Single Aux with instrument                            │
│  ├── Multiple MIDI tracks routed to it                     │
│  ├── Each MIDI track → different channel                   │
│  └── Useful for: Complex orchestral templates              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 7.5 Plugin Delay Compensation

```
┌─────────────────────────────────────────────────────────────┐
│             PLUGIN DELAY COMPENSATION                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Kako ADC radi za plugins:                                   │
│                                                              │
│  1. Plugin reports latency → Pro Tools                      │
│  2. Pro Tools calculates total system latency              │
│  3. Finds track with highest latency                       │
│  4. Delays all other tracks to match                       │
│  5. Result: Phase-coherent playback                        │
│                                                              │
│  Plugin Types by Latency:                                    │
│                                                              │
│  ZERO LATENCY (0 samples):                                   │
│  ├── Simple EQs (IIR filters)                              │
│  ├── Dynamics without lookahead                            │
│  ├── Saturation/distortion                                 │
│  └── Most real-time effects                                │
│                                                              │
│  LOW LATENCY (< 256 samples):                               │
│  ├── Lookahead dynamics                                    │
│  ├── Some amp sims                                         │
│  └── Basic convolution                                     │
│                                                              │
│  MEDIUM LATENCY (256-1024 samples):                         │
│  ├── Complex dynamics                                      │
│  ├── Some mastering processors                             │
│  └── Oversampled plugins                                   │
│                                                              │
│  HIGH LATENCY (> 1024 samples):                             │
│  ├── Linear phase EQ                                       │
│  ├── Heavy convolution reverbs                             │
│  ├── Complex restoration tools                             │
│  └── Spectral processors                                   │
│                                                              │
│  Viewing Latency in Pro Tools:                               │
│  ├── View > Mix Window > Delay Compensation                │
│  ├── Shows per-track delay values                          │
│  ├── "dly" = plugin latency (samples)                      │
│  ├── "cmp" = compensation applied (samples)                │
│  └── Colors: Green (OK), Orange (highest), Red (problem)   │
│                                                              │
│  Problem Scenarios:                                          │
│  ├── Badly coded plugins (don't report latency)            │
│  ├── Plugins that change latency during playback           │
│  ├── Complex routing (parallel paths)                      │
│  └── External hardware inserts                             │
│                                                              │
│  Solutions:                                                   │
│  ├── Report bug to plugin developer                        │
│  ├── Use TimeAdjuster plugin for manual compensation       │
│  ├── Commit/Freeze problematic tracks                      │
│  └── H/W Insert Delay settings for hardware                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. PROJECT/SESSION MANAGEMENT

### 8.1 Session Structure (.ptx, .ptf legacy)

```
┌─────────────────────────────────────────────────────────────┐
│                   SESSION FILE FORMATS                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Current Format: .ptx (Pro Tools 10+)                       │
│                                                              │
│  Session File (.ptx) Contains:                               │
│  ├── Track configuration                                    │
│  ├── Mixer settings (all parameters)                        │
│  ├── Plugin assignments and settings                        │
│  ├── Clip references (NOT audio data)                       │
│  ├── Edit decisions (fades, clip positions)                 │
│  ├── Automation data                                        │
│  ├── MIDI data                                              │
│  ├── Memory Locations                                       │
│  ├── I/O settings                                           │
│  └── Video references                                       │
│                                                              │
│  Session File Does NOT Contain:                              │
│  ├── Audio files (separate folder)                         │
│  ├── Video files (separate folder)                         │
│  ├── Plugin installers                                     │
│  └── Fonts/assets                                          │
│                                                              │
│  Legacy Formats:                                             │
│  ├── .ptf — Pro Tools 7-9                                  │
│  ├── .pts — Pro Tools 5.1-6.9                              │
│  └── Can open old, save as new                             │
│                                                              │
│  Session Folder Structure:                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ My Session/                                             │ │
│  │ ├── My Session.ptx          ← Session file             │ │
│  │ ├── Audio Files/            ← All audio                │ │
│  │ │   ├── Track 1_01.wav                                 │ │
│  │ │   ├── Track 1_02.wav                                 │ │
│  │ │   └── ...                                            │ │
│  │ ├── Bounced Files/          ← Exported mixes           │ │
│  │ ├── Clip Groups/            ← Clip group data          │ │
│  │ ├── Rendered Files/         ← Freeze files             │ │
│  │ ├── Session File Backups/   ← Auto-save backups        │ │
│  │ │   ├── My Session.bak01.ptx                           │ │
│  │ │   └── My Session.bak02.ptx                           │ │
│  │ ├── Video Files/            ← Video media              │ │
│  │ └── WaveCache.wfm           ← Waveform cache           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  KRITIČNO: Session = CELI FOLDER, ne samo .ptx fajl!        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Session Templates

```
┌─────────────────────────────────────────────────────────────┐
│                   SESSION TEMPLATES                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Svrha:                                                      │
│  ├── Pre-configured session starting points                 │
│  ├── Consistent workflows                                   │
│  ├── Faster session setup                                   │
│  └── Team standardization                                   │
│                                                              │
│  Template Contents:                                          │
│  ├── Track layout                                           │
│  ├── Routing (buses, I/O)                                   │
│  ├── Default plugins                                        │
│  ├── Memory Locations                                       │
│  ├── Groups                                                 │
│  ├── Window Configurations                                  │
│  ├── I/O Settings                                           │
│  └── Markers                                                │
│                                                              │
│  Creating Templates:                                         │
│  1. Build session with desired configuration                │
│  2. Remove any project-specific content                     │
│  3. File > Save As Template                                 │
│  4. Name and categorize                                     │
│                                                              │
│  Template Locations:                                         │
│  ├── Factory: Built-in Pro Tools templates                 │
│  ├── User: Your custom templates                           │
│  └── Custom path: Setup > Preferences > Operation >        │
│                   Session Templates folder                  │
│                                                              │
│  Using Templates:                                            │
│  ├── File > New (shows Template dialog)                    │
│  ├── Or File > New From Template                           │
│  └── Ctrl+N / Cmd+N                                        │
│                                                              │
│  Common Template Types:                                      │
│  ├── Recording (tracking rooms)                            │
│  ├── Mixing (stem setup)                                   │
│  ├── Mastering (stereo/surround)                           │
│  ├── Post-Production (dialogue, Foley, mix)                │
│  ├── Podcast/Voiceover                                     │
│  └── Music genres (orchestra, rock, electronic)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 8.3 Import Session Data

```
┌─────────────────────────────────────────────────────────────┐
│                 IMPORT SESSION DATA                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Access: File > Import > Session Data                       │
│                                                              │
│  Svrha:                                                      │
│  ├── Import tracks from other sessions                      │
│  ├── Import from AAF/OMF                                    │
│  ├── Selective import (cherry-pick elements)               │
│  └── Session merge workflows                                │
│                                                              │
│  Import Options:                                             │
│                                                              │
│  TRACK DATA:                                                 │
│  ├── All tracks                                             │
│  ├── Selected tracks only                                   │
│  └── Match by: Name, ID, or create new                     │
│                                                              │
│  PER-TRACK OPTIONS:                                          │
│  ├── Track Type                                             │
│  ├── I/O assignments                                        │
│  ├── Inserts                                                │
│  ├── Sends                                                  │
│  ├── Automation                                             │
│  ├── Clips                                                  │
│  └── Clip Gain                                              │
│                                                              │
│  SESSION DATA:                                               │
│  ├── Tempo/Meter map                                        │
│  ├── Key signature                                          │
│  ├── Markers/Memory Locations                               │
│  └── Window Configurations                                  │
│                                                              │
│  MEDIA OPTIONS:                                              │
│  ├── Link to source                                         │
│  ├── Copy from source                                       │
│  ├── Consolidate from source                                │
│  └── Convert sample rate/bit depth                         │
│                                                              │
│  TIME OPTIONS (2024+):                                       │
│  ├── Adjust Session Start Time to Match Source             │
│  ├── Maintain Absolute Timecode Position                   │
│  └── Maintain Relative Position                            │
│                                                              │
│  Import Modes (2024.10):                                     │
│  ├── NEW: Unlinked track selection                          │
│  ├── Select tracks, choose action                          │
│  ├── Repeat for different groups                           │
│  └── More flexible import workflows                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 8.4 AAF/OMF Exchange

```
┌─────────────────────────────────────────────────────────────┐
│                    AAF/OMF EXCHANGE                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  OMF (Open Media Framework):                                 │
│  ├── Older standard                                         │
│  ├── Basic track/clip exchange                              │
│  ├── Limited metadata                                       │
│  └── Deprecated — use AAF when possible                    │
│                                                              │
│  AAF (Advanced Authoring Format):                            │
│  ├── Modern standard                                        │
│  ├── Richer metadata support                                │
│  ├── Includes: Clips, fades, clip gain, automation         │
│  ├── Video reference support                                │
│  └── Industry standard for post-production                  │
│                                                              │
│  Export AAF/OMF:                                             │
│  File > Export > Selected Tracks as AAF/OMF                │
│                                                              │
│  Export Options:                                             │
│  ├── Format: AAF ili OMF                                   │
│  ├── Audio: Embedded ili Separate folder                   │
│  ├── Audio Format: BWF, AIFF, SD2                          │
│  ├── Bit Depth: Same, 16, 24, 32                           │
│  ├── Sample Rate: Same ili convert                         │
│  ├── Include: Clip gain, automation, fades                 │
│  └── Handles: Extra audio at clip boundaries               │
│                                                              │
│  Import AAF/OMF:                                             │
│  ├── File > Import > Session Data                          │
│  ├── Navigate to .aaf ili .omf file                        │
│  └── Use Import Session Data options                       │
│                                                              │
│  Common Workflow (Video Post):                               │
│  1. Picture editor exports AAF from Avid/Premiere          │
│  2. Sound editor imports into Pro Tools                     │
│  3. Audio work done in Pro Tools                           │
│  4. Export AAF back to picture editor                      │
│  └── Or deliver stems separately                           │
│                                                              │
│  Troubleshooting:                                            │
│  ├── Missing media: Relink in session                      │
│  ├── Wrong timecode: Check session start time              │
│  ├── Clip gain missing: AAF version compatibility          │
│  └── Fades missing: Check export options                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 8.5 Session Backup & Disk Allocation

```
┌─────────────────────────────────────────────────────────────┐
│           SESSION BACKUP & DISK ALLOCATION                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  AUTO-SAVE (Session File Backups):                           │
│  ├── Location: Session folder/Session File Backups/        │
│  ├── Setup: Preferences > Operation > Auto Backup          │
│  ├── Options:                                               │
│  │   ├── Keep most recent: 1-999 backups                   │
│  │   ├── Backup every: 1-60 minutes                        │
│  │   └── Save location                                     │
│  ├── Naming: SessionName.bak01.ptx, .bak02.ptx, etc.       │
│  └── Incrementing numbers (oldest = lowest)                │
│                                                              │
│  SAVE COPY IN:                                               │
│  ├── File > Save Copy In                                   │
│  ├── Creates complete session package                       │
│  ├── Options:                                               │
│  │   ├── Items to Copy: All audio, selected, none          │
│  │   ├── Audio file format conversion                      │
│  │   ├── Sample rate conversion                            │
│  │   └── Bit depth conversion                              │
│  └── Ideal za: Sharing, archiving, format change           │
│                                                              │
│  DISK ALLOCATION:                                            │
│  ├── Setup > Disk Allocation                               │
│  ├── Assigns recording drives per track                    │
│  ├── Options:                                               │
│  │   ├── Root folder (default location)                    │
│  │   ├── Per-track assignment                              │
│  │   └── Round-robin recording                             │
│  ├── Use za: Spreading load across drives                  │
│  └── Important za: High track count recording              │
│                                                              │
│  WORKSPACE BROWSER:                                          │
│  ├── Window > Workspace                                    │
│  ├── Functions:                                             │
│  │   ├── Browse all connected drives                       │
│  │   ├── Designate drives (R = Record, P = Playback, T)   │
│  │   ├── Audition audio files                              │
│  │   ├── Drag files into session                           │
│  │   └── Search across volumes                             │
│  ├── Volume Designations:                                   │
│  │   ├── R (Record): Audio can be recorded                │
│  │   ├── P (Playback): Audio can play back                │
│  │   └── T (Transfer): Transfer volume only               │
│  └── Important: System drive should be P only              │
│                                                              │
│  BEST PRACTICES:                                             │
│  ├── Keep session + audio on FAST drive (SSD/NVMe)         │
│  ├── Backup entire session folder regularly                │
│  ├── Use Save Copy In for archiving                        │
│  ├── Never record to system drive                          │
│  ├── Auto-backup every 5-10 minutes                        │
│  └── Test restoring from backup periodically               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

*Dokument se nastavlja u Part 4...*
# Pro Tools 2024 — Ultra-Detaljna Tehnička Analiza (Part 4)

---

## 9. METERING & VISUALIZATION

### 9.1 Track Meters (Pre/Post)

```
┌─────────────────────────────────────────────────────────────┐
│                     TRACK METERING                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Meter Position Options:                                     │
│  ├── PRE-FADER: Measures signal before fader               │
│  │   └── Shows input level, unaffected by fader moves     │
│  └── POST-FADER: Measures signal after fader               │
│      └── Shows what's actually being sent out              │
│                                                              │
│  Setting: Options > Pre-Fader Metering (toggle)             │
│  ├── ON = Pre-fader                                        │
│  └── OFF = Post-fader                                      │
│                                                              │
│  Meter Types (Pro Tools Studio/Ultimate):                    │
│                                                              │
│  1. SAMPLE PEAK                                              │
│     ├── Fastest response                                    │
│     ├── Shows true digital peaks                           │
│     └── Industry standard for digital clipping detection   │
│                                                              │
│  2. PRO TOOLS CLASSIC                                        │
│     ├── Original Pro Tools metering                        │
│     ├── Smooth, easy to read                               │
│     └── Good general-purpose meter                         │
│                                                              │
│  3. LINEAR                                                   │
│     ├── Linear scale (not logarithmic)                     │
│     ├── More sensitive at high levels                      │
│     └── Variations: Linear, Linear (Extended)              │
│                                                              │
│  4. RMS                                                      │
│     ├── Root Mean Square                                   │
│     ├── Shows average level (perceived loudness)           │
│     └── Slower response than peak                          │
│                                                              │
│  5. VU (Volume Unit)                                         │
│     ├── Analog VU meter emulation                          │
│     ├── 300ms integration time                             │
│     ├── Variations: VU, VU+6, VU+12                        │
│     └── Reference level adjustable                         │
│                                                              │
│  6. PPM (Peak Program Meter)                                 │
│     ├── Broadcast standard metering                        │
│     ├── Variations:                                        │
│     │   ├── BBC PPM (UK standard)                         │
│     │   ├── DIN PPM (European)                            │
│     │   ├── Nordic PPM                                    │
│     │   ├── EBU PPM                                       │
│     │   └── SMPTE RP155                                   │
│     └── Fast attack, slow release                          │
│                                                              │
│  7. K-SYSTEM (Bob Katz)                                      │
│     ├── Reference-calibrated metering                      │
│     ├── Variations:                                        │
│     │   ├── K-12 (Broadcast)                              │
│     │   ├── K-14 (Pop/Rock)                               │
│     │   └── K-20 (Classical/Film)                         │
│     └── 0dB = RMS reference level                          │
│                                                              │
│  8. VENUE Peak + RMS                                         │
│     └── Shows both peak and RMS simultaneously             │
│                                                              │
│  Meter Setup: Setup > Preferences > Metering                │
│  ├── Peak Hold: Off, 3-sec, Infinite                       │
│  ├── Clip Indication: Hold time                            │
│  └── Track meter type selection                            │
│                                                              │
│  NAPOMENA: Pro Tools NEMA ugrađen LUFS metering!            │
│  └── Koristi third-party plugin (Youlean, Nugen, etc.)     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 9.2 Meter Bridge

```
┌─────────────────────────────────────────────────────────────┐
│                     METER BRIDGE                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept: Large meter display above Mix window              │
│                                                              │
│  Access: Window > Mix Window > Narrow Mix (disables)        │
│          Track height affects meter size                    │
│                                                              │
│  Display Options:                                            │
│  ├── View > Mix Window > Narrow Mix (OFF for big meters)   │
│  ├── Track height: Larger = bigger meters                  │
│  └── View > Edit Window > Show Track Meters                │
│                                                              │
│  Third-Party Meter Bridges:                                  │
│  ├── AVID Space: Hardware meter bridge                     │
│  ├── Software options: Nugen VisLM, iZotope Insight        │
│  └── EUCON surfaces: Built-in metering                     │
│                                                              │
│  What Pro Tools Shows:                                       │
│  ├── Per-track meters (width matches format)               │
│  ├── Output meters on Master Fader                         │
│  ├── Send meters (when sends visible)                      │
│  └── Bus meters (on Aux tracks)                            │
│                                                              │
│  What Pro Tools Doesn't Have (natively):                     │
│  ├── Dedicated master section meters                       │
│  ├── Spectrum analyzer                                     │
│  ├── Phase correlation meter                               │
│  ├── Loudness meter (LUFS)                                 │
│  └── Standalone meter bridge window                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 9.3 Loudness Metering (LUFS)

```
┌─────────────────────────────────────────────────────────────┐
│               LOUDNESS METERING (LUFS)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  KRITIČNO: Pro Tools NEMA native LUFS metering!             │
│                                                              │
│  Zašto je ovo problem:                                       │
│  ├── Streaming platforms zahtevaju LUFS normalizaciju       │
│  ├── Broadcast standardi (EBU R128) zahtevaju LUFS         │
│  └── Mastering bez LUFS je nepotpun                        │
│                                                              │
│  Rešenje — Third-Party Plugins:                              │
│                                                              │
│  FREE OPTIONS:                                               │
│  ├── Youlean Loudness Meter 2 (Preporučeno)                │
│  │   ├── LUFS, True Peak, Dynamic Range                    │
│  │   ├── Free version fully functional                     │
│  │   └── AAX Native format                                 │
│  │                                                          │
│  └── APU Loudness Meter                                     │
│      ├── LUFS, RMS, Peak, True Peak                        │
│      └── Simple, clean interface                           │
│                                                              │
│  PAID OPTIONS:                                               │
│  ├── Nugen Audio VisLM                                     │
│  │   ├── Industry standard                                 │
│  │   └── Comprehensive loudness analysis                   │
│  │                                                          │
│  ├── iZotope Insight 2                                     │
│  │   ├── Full metering suite                               │
│  │   ├── Spectrum, loudness, phase, stereo                 │
│  │   └── History graph                                     │
│  │                                                          │
│  ├── Mastering The Mix LEVELS                              │
│  │   ├── Target-based metering                             │
│  │   └── Preset targets for platforms                      │
│  │                                                          │
│  └── Avid Pro Limiter (Bundled with subscriptions)         │
│      ├── True peak limiting                                │
│      └── R128 loudness meter built-in                      │
│                                                              │
│  LUFS Target Levels:                                         │
│  ┌───────────────────┬────────────────┐                    │
│  │ Platform          │ Target LUFS    │                    │
│  ├───────────────────┼────────────────┤                    │
│  │ Spotify           │ -14 LUFS       │                    │
│  │ Apple Music       │ -16 LUFS       │                    │
│  │ YouTube           │ -14 LUFS       │                    │
│  │ Amazon Music      │ -14 LUFS       │                    │
│  │ Tidal             │ -14 LUFS       │                    │
│  │ Broadcast (EU)    │ -23 LUFS       │                    │
│  │ Broadcast (US)    │ -24 LUFS       │                    │
│  │ CD/Club           │ -8 to -10 LUFS │                    │
│  └───────────────────┴────────────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 9.4 Phase & Stereo Analysis

```
┌─────────────────────────────────────────────────────────────┐
│            PHASE & STEREO VISUALIZATION                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Native Pro Tools: NEMA phase scope ili stereo imager       │
│                                                              │
│  Third-Party Solutions:                                      │
│                                                              │
│  1. PHASE CORRELATION METER                                  │
│     ├── Shows L/R relationship                             │
│     ├── +1 = Mono (in phase)                               │
│     ├── 0 = Stereo (uncorrelated)                          │
│     ├── -1 = Out of phase (cancellation)                   │
│     └── Plugins: Nugen Stereoizer, SPAN, Ozone            │
│                                                              │
│  2. STEREO VECTORSCOPE/GONIOMETER                           │
│     ├── Visual L/R spread                                  │
│     ├── Lissajous display                                  │
│     ├── Shows stereo width graphically                     │
│     └── Plugins: SPAN, Stereo Tool, s(M)exoscope          │
│                                                              │
│  3. STEREO WIDTH METER                                       │
│     ├── Shows width as percentage                          │
│     ├── Mono compatibility indication                      │
│     └── Plugins: iZotope Insight, Nugen Visualizer        │
│                                                              │
│  Preporučeni Besplatni Alati:                                │
│  ├── Voxengo SPAN (spectrum + correlation)                 │
│  ├── Flux:: Stereo Tool v3 (phase, stereo)                │
│  ├── Blue Cat's FreqAnalyst (spectrum)                     │
│  └── MeldaProduction MAnalyzer (comprehensive)             │
│                                                              │
│  Why Phase Matters:                                          │
│  ├── Mono compatibility (radio, phones)                    │
│  ├── Translation to different systems                      │
│  ├── Bass coherence (mono bass recommended)                │
│  └── Avoiding cancellation artifacts                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 10. UI/UX DESIGN

### 10.1 Edit Window Layout

```
┌─────────────────────────────────────────────────────────────┐
│                   EDIT WINDOW LAYOUT                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ [File] [Edit] [View] [Track] ... [Window] [Help]      │  │
│  │                                                        │  │
│  │ ┌────────────────────────────────────────────────────┐│  │
│  │ │        TOOLBAR (customizable)                      ││  │
│  │ │ [Zoom] [Edit Mode] [Tools] [Grid] [Nudge] [Counters││  │
│  │ └────────────────────────────────────────────────────┘│  │
│  │                                                        │  │
│  │ ┌────────────────────────────────────────────────────┐│  │
│  │ │        RULERS (toggle visibility)                  ││  │
│  │ │ [Markers] [Tempo] [Meter] [Bars:Beats] [Min:Sec]  ││  │
│  │ └────────────────────────────────────────────────────┘│  │
│  │                                                        │  │
│  │ ┌─────┬─────────────────────────────────────┬───────┐│  │
│  │ │     │                                     │       ││  │
│  │ │ T   │         TIMELINE                    │  C    ││  │
│  │ │ R   │         (Tracks & Clips)            │  L    ││  │
│  │ │ A   │                                     │  I    ││  │
│  │ │ C   │  ████  ██████████  ████████████   │  P    ││  │
│  │ │ K   │  ████████████████  ██████         │       ││  │
│  │ │     │  ██████    ████████████████████   │  L    ││  │
│  │ │ L   │                                     │  I    ││  │
│  │ │ I   │                                     │  S    ││  │
│  │ │ S   │                                     │  T    ││  │
│  │ │ T   │                                     │       ││  │
│  │ └─────┴─────────────────────────────────────┴───────┘│  │
│  │                                                        │  │
│  │ ┌────────────────────────────────────────────────────┐│  │
│  │ │        TRANSPORT (optional floating)               ││  │
│  │ └────────────────────────────────────────────────────┘│  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  View Menu Options:                                          │
│  ├── Narrow Mix: Compact track headers                      │
│  ├── Rulers: Show/hide individual rulers                   │
│  ├── Track List: Show/hide left sidebar                    │
│  ├── Clip List: Show/hide right sidebar                    │
│  ├── MIDI Controls: Show MIDI editing tools                │
│  └── Universe: Session overview (zoom out view)            │
│                                                              │
│  Customization:                                              │
│  ├── Toolbar items can be added/removed                    │
│  ├── Window Configurations save layout                     │
│  ├── Track height: Mini, Small, Medium, Large, etc.       │
│  └── View presets: Store/recall zoom levels                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 10.2 Mix Window Layout

```
┌─────────────────────────────────────────────────────────────┐
│                    MIX WINDOW LAYOUT                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ STRIP VIEW (per channel)                                │ │
│  │                                                         │ │
│  │ ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐           │ │
│  │ │ In  │  │ In  │  │ In  │  │ In  │  │ In  │  Inserts   │ │
│  │ │ A-E │  │ A-E │  │ A-E │  │ A-E │  │ A-E │  A-E       │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │Send │  │Send │  │Send │  │Send │  │Send │  Sends     │ │
│  │ │ A-E │  │ A-E │  │ A-E │  │ A-E │  │ A-E │  A-E       │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │ In  │  │ In  │  │ In  │  │ In  │  │ In  │  Inserts   │ │
│  │ │ F-J │  │ F-J │  │ F-J │  │ F-J │  │ F-J │  F-J       │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │Send │  │Send │  │Send │  │Send │  │Send │  Sends     │ │
│  │ │ F-J │  │ F-J │  │ F-J │  │ F-J │  │ F-J │  F-J       │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │ I/O │  │ I/O │  │ I/O │  │ I/O │  │ I/O │  I/O       │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │  Meters   │ │
│  │ │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │  │ ▄▄▄ │           │ │
│  │ │ ███ │  │ █▄▄ │  │ ▄█▄ │  │ ██▄ │  │ ▄██ │           │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │ ──  │  │ ──  │  │ ──  │  │ ──  │  │ ──  │  Pan      │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │     │  │     │  │     │  │     │  │     │           │ │
│  │ │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  Fader    │ │
│  │ │  │  │  │  │  │  │  │  │  │  │  │  │  │  │           │ │
│  │ │  ●  │  │  ●  │  │  ●  │  │  ●  │  │  ●  │           │ │
│  │ │  │  │  │  │  │  │  │  │  │  │  │  │  │  │           │ │
│  │ ├─────┤  ├─────┤  ├─────┤  ├─────┤  ├─────┤           │ │
│  │ │[S][M]│ │[S][M]│ │[S][M]│ │[S][M]│ │[S][M]│ Solo/Mute│ │
│  │ │Track │  │Track │  │Track │  │Track │  │Track │ Name   │ │
│  │ │ 1    │  │ 2    │  │ 3    │  │ 4    │  │ 5    │        │ │
│  │ └─────┘  └─────┘  └─────┘  └─────┘  └─────┘           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  View Options (View > Mix Window):                           │
│  ├── Instruments: Show/hide instrument slot                │
│  ├── Inserts A-E / F-J: Pre/post fader inserts            │
│  ├── Sends A-E / F-J: Pre/post fader sends                │
│  ├── Track I/O: Input/output assignments                   │
│  ├── Comments: Track comments field                        │
│  ├── Delay Compensation: Plugin latency display            │
│  ├── Track Color: Color bar                                │
│  └── All: Show everything                                  │
│                                                              │
│  Narrow Mix Mode:                                            │
│  ├── Options > Narrow Mix                                  │
│  ├── Reduces channel strip width                           │
│  └── Fits more tracks on screen                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 10.3 Keyboard Focus Modes (JEDINSTVENO!)

```
┌─────────────────────────────────────────────────────────────┐
│        KEYBOARD COMMANDS FOCUS MODE (Pro Tools EXCLUSIVE)    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Pretvara QWERTY tastaturu u shortcut paletu            │
│  ├── Single-key commands (bez modifiera)                    │
│  ├── EKSKLUZIVNO za Pro Tools — nijedan drugi DAW nema!    │
│  └── Drastično ubrzava editing workflow                     │
│                                                              │
│  Enable/Disable:                                             │
│  ├── Click [a...z] button (below zoom in Edit Window)      │
│  ├── Yellow = Active                                        │
│  └── Shortcut: Opt+Cmd+1 / Alt+Ctrl+1                      │
│                                                              │
│  TRI FOCUS MODA:                                             │
│                                                              │
│  1. COMMANDS FOCUS (Edit Window)                             │
│     Location: [a...z] button in Edit Window                 │
│     ├── Single keys = editing commands                      │
│     ├── Numbers = zoom presets                              │
│     └── Letters = edit/transport commands                   │
│                                                              │
│  2. CLIP LIST FOCUS                                          │
│     Location: [a...z] button in Clip List                   │
│     ├── Type letter = jump to clips starting with letter   │
│     ├── Quick navigation                                    │
│     └── Useful for finding clips by name                   │
│                                                              │
│  3. GROUPS LIST FOCUS                                        │
│     Location: [a...z] button in Groups List                 │
│     ├── Type letter = enable/disable group by letter       │
│     └── Quick group toggling                                │
│                                                              │
│  COMMANDS FOCUS — Key Shortcuts:                             │
│                                                              │
│  EDITING KEYS:                                               │
│  ├── B: Separate clip at selection (Break)                 │
│  ├── A: Trim clip start to cursor                          │
│  ├── S: Trim clip end to cursor                            │
│  ├── D: Create fade IN to cursor                           │
│  ├── G: Create fade OUT from cursor                        │
│  ├── F: Create crossfade at selection                      │
│  └── T: Trim tool / select Trim                            │
│                                                              │
│  PLAYBACK KEYS:                                              │
│  ├── 6: Play from pre-roll to start of selection           │
│  ├── 7: Play from selection start using post-roll          │
│  ├── 8: Play to end of selection using pre-roll            │
│  ├── 9: Play from end of selection using post-roll         │
│  └── L: Loop playback toggle                               │
│                                                              │
│  SELECTION KEYS:                                             │
│  ├── O: Copy Edit selection to Timeline                    │
│  ├── 0: Copy Timeline selection to Edit                    │
│  ├── Tab: Move cursor to next transient/clip               │
│  └── Opt+Tab: Move cursor to previous                      │
│                                                              │
│  NAVIGATION KEYS:                                            │
│  ├── , (comma): Nudge selection earlier                    │
│  ├── . (period): Nudge selection later                     │
│  ├── M: Nudge earlier by larger amount                     │
│  ├── / (slash): Nudge later by larger amount               │
│  └── Enter: Create Memory Location at cursor               │
│                                                              │
│  TOGGLE KEYS:                                                │
│  ├── N: Insertion follows playback toggle                  │
│  ├── - (minus): Toggle track view (waveform/volume)        │
│  └── P: Pencil tool                                        │
│                                                              │
│  VIEW KEYS:                                                  │
│  ├── R: Zoom tool                                          │
│  ├── E: Smart tool enable                                  │
│  ├── 1-5: Zoom preset recall                               │
│  └── Ctrl+1-5: Store zoom preset                           │
│                                                              │
│  ZAŠTO JE OVO REVOLUCIONARNO:                                │
│  ├── Editing sa jednom rukom dok druga drži mouse          │
│  ├── Ne treba gledati tastaturu                            │
│  ├── Workflow 2-3x brži nego u drugim DAW-ovima            │
│  └── Post-production workflow — industriski standard       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 10.4 Window Configurations

```
┌─────────────────────────────────────────────────────────────┐
│                 WINDOW CONFIGURATIONS                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Kapacitet: Up to 99 configurations                         │
│                                                              │
│  Access: Window > Configurations > [Configuration]          │
│                                                              │
│  What Gets Stored:                                           │
│  ├── Window positions (x, y coordinates)                   │
│  ├── Window sizes (width, height)                          │
│  ├── Window visibility (open/closed)                       │
│  ├── Edit Window layout (rulers, sidebars)                 │
│  ├── Mix Window strip visibility                           │
│  ├── Track heights (Edit Window)                           │
│  ├── Track widths (Mix Window — Narrow Mix)                │
│  └── Floating window positions (Transport, etc.)           │
│                                                              │
│  Creating Configuration:                                     │
│  1. Arrange windows as desired                              │
│  2. Window > Configurations > New Configuration             │
│  3. Name the configuration                                  │
│  4. Set options:                                            │
│     ├── Window Layout: Positions and sizes                 │
│     ├── Include Edit Window Display Settings              │
│     └── Number (1-99)                                      │
│                                                              │
│  Recalling Configuration:                                    │
│  ├── Window > Configurations > [Name]                      │
│  ├── Number Pad: . + Number + * (asterisk)                 │
│  │   Example: .1* recalls configuration 1                  │
│  └── Memory Location with Window Config linked             │
│                                                              │
│  Common Configurations:                                      │
│  ├── "Edit": Full Edit Window, floating Transport          │
│  ├── "Mix": Full Mix Window                                │
│  ├── "Edit+Mix": Split screen                              │
│  ├── "MIDI": Edit + MIDI Editor                            │
│  ├── "Tracking": Edit with large meters                    │
│  └── "Review": Compact for client viewing                  │
│                                                              │
│  Pro Tip:                                                    │
│  └── Link Window Configs to Memory Locations za            │
│      automatic view switching pri navigaciji               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. HARDWARE INTEGRATION

### 11.1 HDX Cards

```
┌─────────────────────────────────────────────────────────────┐
│                      HDX CARD SYSTEM                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Hardware: PCIe card sa dedicated DSP                       │
│                                                              │
│  Per-Card Specifications:                                    │
│  ├── 18 TI DSP procesora                                   │
│  ├── 2 high-performance FPGA chips                         │
│  ├── Dedicated FPGA za 64-bit mix bus                      │
│  ├── 6.3 GHz ukupne procesne snage                         │
│  └── 2× DigiLink Mini ports                                │
│                                                              │
│  System Configurations:                                      │
│  ┌──────────┬────────┬─────────┬──────────┬────────────┐   │
│  │ Config   │ Cards  │ Voices  │ I/O      │ DSP Power  │   │
│  │          │        │ @48kHz  │ Channels │            │   │
│  ├──────────┼────────┼─────────┼──────────┼────────────┤   │
│  │ HDX 1    │ 1      │ 256     │ 64       │ 6.3 GHz    │   │
│  │ HDX 2    │ 2      │ 512     │ 128      │ 12.6 GHz   │   │
│  │ HDX 3    │ 3      │ 768     │ 192      │ 18.9 GHz   │   │
│  └──────────┴────────┴─────────┴──────────┴────────────┘   │
│                                                              │
│  DigiLink Connections:                                       │
│  ├── DigiLink Mini (newer) ili DigiLink (legacy)           │
│  ├── Connect to: HD I/O, HD OMNI, HD MADI                  │
│  ├── Each port: up to 32 I/O channels                      │
│  └── Total: 64 I/O per card (2 ports)                      │
│                                                              │
│  Compatible Interfaces:                                      │
│  ├── Pro Tools | HD I/O (8×8, 16×16 configurations)        │
│  ├── Pro Tools | HD OMNI (all-in-one)                      │
│  ├── Pro Tools | HD MADI (64 channels digital)             │
│  ├── Third-party DigiLink interfaces                       │
│  └── Pro Tools | Carbon (Hybrid HDX)                       │
│                                                              │
│  Hybrid Engine:                                              │
│  ├── Combines HDX DSP + Host Native processing             │
│  ├── Per-track DSP/Native selection                        │
│  ├── 2048 voices total (regardless of HDX card count)      │
│  └── Best of both worlds: Low latency DSP + CPU power      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.2 Carbon Interface

```
┌─────────────────────────────────────────────────────────────┐
│                   PRO TOOLS | CARBON                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept: Hybrid audio interface sa ugrađenim HDX DSP       │
│                                                              │
│  I/O Specifications:                                         │
│  ├── 8× Combo mic/line inputs (XLR/TRS)                    │
│  │   └── Variable Z on inputs 5-8                          │
│  ├── 8× Line inputs (DB25)                                 │
│  ├── 2× Instrument inputs (Variable Z)                     │
│  ├── 8× Line outputs (DB25)                                │
│  ├── 2× Monitor outputs (TRS)                              │
│  ├── 4× Stereo headphone outputs                           │
│  ├── 16× ADAT inputs @ 44.1-96kHz (8 @ 176.4-192kHz)       │
│  ├── 16× ADAT outputs @ 44.1-96kHz (8 @ 176.4-192kHz)      │
│  └── Word clock in/out                                     │
│                                                              │
│  Audio Quality:                                              │
│  ├── Up to 32-bit/192kHz                                   │
│  ├── Double precision clocking                             │
│  └── Premium mic preamps                                   │
│                                                              │
│  HDX DSP Features:                                           │
│  ├── On-board DSP processing                               │
│  ├── Near-zero latency monitoring (<1ms)                   │
│  ├── AAX DSP plugin support                                │
│  ├── Process through plugins during tracking               │
│  └── No PCIe card required                                 │
│                                                              │
│  Connectivity:                                               │
│  ├── Thunderbolt 3 (USB-C connector)                       │
│  ├── Compatible with Thunderbolt 2 via adapter             │
│  └── macOS and Windows support                             │
│                                                              │
│  Included Software:                                          │
│  ├── Pro Tools | Ultimate perpetual license                │
│  ├── Complete Plugin Bundle                                │
│  └── Premium support                                       │
│                                                              │
│  Ideal For:                                                  │
│  ├── Studios wanting HDX power without PCIe cards          │
│  ├── Mobile HDX production                                 │
│  ├── Artist/producer studios                               │
│  └── Hybrid laptop/desktop workflows                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.3 Control Surfaces

```
┌─────────────────────────────────────────────────────────────┐
│                   CONTROL SURFACES                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PROTOKOLI:                                                  │
│                                                              │
│  1. EUCON (Ethernet)                                         │
│     ├── Most comprehensive Pro Tools integration           │
│     ├── High-speed Ethernet communication                  │
│     ├── Full parameter access                              │
│     ├── Soft keys programmable                             │
│     └── Avid proprietary (formerly Euphonix)               │
│                                                              │
│  2. HUI (MIDI)                                               │
│     ├── Mackie HUI protocol                                │
│     ├── 8 faders, transport, some functions                │
│     ├── Limited compared to EUCON                          │
│     └── Legacy but widely supported                        │
│                                                              │
│  3. MCU (Mackie Control Universal)                           │
│     ├── Similar to HUI                                     │
│     ├── Generic MIDI control                               │
│     └── Basic functionality                                │
│                                                              │
│  AVID EUCON SURFACE LINEUP:                                  │
│                                                              │
│  S6 (Flagship)                                               │
│  ├── Modular console replacement                           │
│  ├── Customizable configuration                            │
│  ├── Touchscreen integration                               │
│  ├── Complete Pro Tools control                            │
│  └── Price: $100,000+                                      │
│                                                              │
│  S4                                                          │
│  ├── Smaller modular system                                │
│  ├── 8, 16, or 24 fader configurations                     │
│  ├── Same features as S6                                   │
│  └── Price: $24,000+                                       │
│                                                              │
│  S3 (Discontinued 2021)                                      │
│  ├── 16-fader surface                                      │
│  ├── EUCON + HUI + MCU support                             │
│  ├── Touchscreen                                           │
│  └── Replaced by S4                                        │
│                                                              │
│  S1                                                          │
│  ├── 8-fader desktop surface                               │
│  ├── EUCON + HUI + MCU support                             │
│  ├── Touch-sensitive motorized faders                      │
│  ├── OLED displays                                         │
│  ├── Up to 4 units can be daisy-chained                    │
│  └── Price: ~$1,500                                        │
│                                                              │
│  Pro Tools | Dock                                            │
│  ├── iPad-based controller                                 │
│  ├── Works with Avid Control app                           │
│  ├── EUCON integration                                     │
│  └── One per system max                                    │
│                                                              │
│  Third-Party HUI/MCU Surfaces:                               │
│  ├── Behringer X-Touch (8 faders)                          │
│  ├── Icon Platform M+ (motorized faders)                   │
│  ├── PreSonus Faderport (1-16 faders)                      │
│  ├── Solid State Logic UF8                                 │
│  └── Softube Console 1                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.4 Sync & Video

```
┌─────────────────────────────────────────────────────────────┐
│                    SYNC & VIDEO                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SYNC SOURCES:                                               │
│                                                              │
│  1. Internal (Pro Tools generates)                          │
│  2. Word Clock (from external device)                       │
│  3. Video Reference (blackburst, tri-level)                │
│  4. ADAT (from optical connection)                          │
│  5. S/PDIF (from digital input)                            │
│  6. MADI (from MADI connection)                            │
│  7. LTC (Linear Timecode)                                   │
│  8. MTC (MIDI Timecode)                                     │
│                                                              │
│  SYNC PERIPHERALS:                                           │
│                                                              │
│  Pro Tools | SYNC HD                                         │
│  ├── Word clock master                                     │
│  ├── Video sync (bi/tri-level)                             │
│  ├── LTC/VITC/MTC conversion                               │
│  ├── Pull up/down (±0.1%, ±4%)                             │
│  ├── Varispeed                                             │
│  └── DigiLink connection to HDX                            │
│                                                              │
│  VIDEO SATELLITE:                                            │
│  ├── Separate Mac za video playback                        │
│  ├── Offloads video dari main Pro Tools                    │
│  ├── Sample-accurate sync                                  │
│  ├── Supports high-res video (4K)                          │
│  └── Ethernet connection to main system                    │
│                                                              │
│  TIMECODE FORMATS:                                           │
│  ├── 23.976 fps — Film (NTSC-compatible)                   │
│  ├── 24 fps — Film (standard)                              │
│  ├── 25 fps — PAL/SECAM video                              │
│  ├── 29.97 fps — NTSC video                                │
│  ├── 29.97 fps DF — NTSC drop-frame                        │
│  ├── 30 fps — NTSC non-drop (legacy)                       │
│  ├── 30 fps DF — Drop-frame variant                        │
│  ├── 47.95 fps — High frame rate                           │
│  ├── 48 fps — High frame rate                              │
│  ├── 50 fps — PAL high frame rate                          │
│  ├── 59.94 fps — NTSC high frame rate                      │
│  └── 60 fps — High frame rate                              │
│                                                              │
│  VIDEO IN PRO TOOLS:                                         │
│  ├── Enable: Setup > Playback Engine > Video Engine        │
│  ├── Import: File > Import > Video                         │
│  ├── Formats: QuickTime, AVI, MXF                          │
│  ├── Codecs: H.264, H.265, ProRes, DNxHD                   │
│  └── Track: Video track in Edit Window                     │
│                                                              │
│  VIDEO WINDOW:                                               │
│  ├── Window > Video Window                                 │
│  ├── Resizable floating window                             │
│  ├── Full-screen option                                    │
│  ├── Separate display output (SDI via hardware)            │
│  └── Timecode overlay                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 12. UNIQUE FEATURES

### 12.1 Dynamic Plugin Processing

```
┌─────────────────────────────────────────────────────────────┐
│              DYNAMIC PLUGIN PROCESSING                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Introduced: Pro Tools 11                                   │
│  Unique to: Pro Tools                                       │
│                                                              │
│  How It Works:                                               │
│  ├── Pro Tools monitors each plugin's audio input          │
│  ├── When no audio passes through → Plugin "sleeps"        │
│  ├── DSP/CPU resources released                            │
│  ├── When audio returns → Plugin instantly "wakes"         │
│  └── Seamless, inaudible transition                        │
│                                                              │
│  Benefits:                                                   │
│  ├── Higher plugin counts                                  │
│  ├── More efficient resource usage                         │
│  ├── Better for sparse arrangements                        │
│  └── Automatic — no user intervention                      │
│                                                              │
│  Ograničenja:                                                │
│  ├── Radi samo na AUX trackovima                           │
│  ├── Audio tracks: plugins ostaju aktivni                  │
│  ├── Plugins with internal state (reverb tails) may glitch│
│  └── Some plugins don't support properly                   │
│                                                              │
│  Enable: Setup > Playback Engine > Dynamic Plug-In Processing│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 12.2 Commit / Freeze / Bounce

```
┌─────────────────────────────────────────────────────────────┐
│               COMMIT / FREEZE / BOUNCE                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. TRACK FREEZE (Snowflake)                                 │
│     ├── Access: Right-click track > Freeze                 │
│     ├── Creates hidden rendered file                       │
│     ├── Track locked — no editing                          │
│     ├── Instant unfreeze to original                       │
│     ├── Uses: Reducing CPU during playback                 │
│     └── Limitation: Can't freeze hardware inserts          │
│                                                              │
│  2. TRACK COMMIT                                             │
│     ├── Access: Right-click track > Commit                 │
│     ├── Creates new audio track with rendered audio        │
│     ├── Original track muted (not deleted)                 │
│     ├── .cm suffix on files                                │
│     ├── Clips appear in Clip List                          │
│     ├── Editable like normal audio                         │
│     └── Uses: Creating stems, sharing sessions             │
│                                                              │
│  3. TRACK BOUNCE                                             │
│     ├── Access: Right-click track > Bounce                 │
│     ├── Creates export-ready file                          │
│     ├── Full format control (WAV, AIFF, MP3, etc.)        │
│     ├── Doesn't create new track                           │
│     └── Uses: Final deliverables, stems for export         │
│                                                              │
│  Comparison:                                                  │
│  ┌────────────┬───────────┬───────────┬────────────┐       │
│  │            │ Freeze    │ Commit    │ Bounce     │       │
│  ├────────────┼───────────┼───────────┼────────────┤       │
│  │ Creates    │ Hidden    │ New track │ File only  │       │
│  │ Editable   │ No        │ Yes       │ N/A        │       │
│  │ Reversible │ Instant   │ Manual    │ N/A        │       │
│  │ Format     │ Internal  │ Internal  │ Full ctrl  │       │
│  │ Purpose    │ CPU save  │ Render    │ Export     │       │
│  └────────────┴───────────┴───────────┴────────────┘       │
│                                                              │
│  Offline vs Real-Time:                                       │
│  ├── Both Commit and Bounce offer Offline option           │
│  ├── Offline: Faster than real-time                        │
│  ├── Real-time: Required for hardware inserts              │
│  └── Sound quality: Identical (files should null)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 12.3 Dolby Atmos Integration

```
┌─────────────────────────────────────────────────────────────┐
│                DOLBY ATMOS INTEGRATION                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Integrated Renderer (2023.12+):                             │
│  ├── Built into Pro Tools Studio/Ultimate                  │
│  ├── No external renderer required                         │
│  ├── Free with subscription                                │
│  └── Full Dolby Atmos authoring capabilities               │
│                                                              │
│  Supported Monitoring Formats:                               │
│  ├── Binaural (headphones)                                 │
│  ├── 2.0 Stereo                                            │
│  ├── 5.1                                                   │
│  ├── 5.1.4                                                 │
│  ├── 7.1                                                   │
│  ├── 7.1.4                                                 │
│  └── 9.1.6 (Pro Tools Ultimate only)                       │
│                                                              │
│  Renderer Features:                                          │
│  ├── Object panning (3D positioning)                       │
│  ├── Bed routing (channel-based)                           │
│  ├── Speaker solo/mute (2024.10)                           │
│  ├── Trim and Downmix window                               │
│  ├── Binaural rendering for headphones                     │
│  ├── Re-renders (simultaneous format creation)             │
│  └── ADM export (master format)                            │
│                                                              │
│  2024.10 Improvements:                                       │
│  ├── Solo/mute individual speakers in renderer             │
│  ├── Solo/mute top/bottom speaker layers                   │
│  ├── Floating Trim/Downmix window                          │
│  └── Improved workflow efficiency                          │
│                                                              │
│  Workflow:                                                   │
│  1. Create Atmos session (template ili manual)             │
│  2. Setup I/O for speaker configuration                    │
│  3. Open internal renderer (Ctrl+Cmd+=)                    │
│  4. Create beds (channel-based) i objects (positioned)     │
│  5. Mix using panners i automation                         │
│  6. Monitor in various formats                             │
│  7. Export ADM BWF master file                             │
│  8. Create re-renders (stereo, 5.1, binaural, etc.)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 12.4 Cloud Collaboration

```
┌─────────────────────────────────────────────────────────────┐
│                 CLOUD COLLABORATION                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept:                                                    │
│  ├── Share Pro Tools sessions via cloud                    │
│  ├── Real-time collaboration (not simultaneous editing)    │
│  ├── Track-level upload/download                           │
│  └── Cross-platform (Mac ↔ Windows)                        │
│                                                              │
│  Session vs Project:                                         │
│  ├── SESSION: Local file (.ptx) — cannot collaborate       │
│  ├── PROJECT: Cloud-synced — collaboration enabled         │
│  └── Convert: File > Save As Project                       │
│                                                              │
│  Collaboration Workflow:                                     │
│  1. Create/convert to Project format                        │
│  2. Invite collaborators (up to 2 simultaneous)            │
│  3. Work on tracks                                         │
│  4. Upload changes (↑ arrow on track)                      │
│  5. Download others' changes (↓ arrow on track)            │
│  6. Resolve any conflicts                                  │
│                                                              │
│  Storage Tiers:                                              │
│  ├── Free: 500MB, 3 projects                               │
│  ├── Subscription includes additional storage              │
│  └── WavPack compression: 30-70% size reduction            │
│                                                              │
│  Plugin Handling:                                            │
│  ├── Collaborator has same plugins → Works normally        │
│  ├── Collaborator missing plugins:                         │
│  │   ├── Use Track Commit/Freeze before sharing           │
│  │   ├── Purchase plugin from Avid Marketplace             │
│  │   └── Or work without those plugins                     │
│  └── Pro Tools notifies of missing plugins                 │
│                                                              │
│  2024.10 Changes:                                            │
│  ├── Collaboration moved from Avid Link to Pro Tools       │
│  ├── Integrated directly into application                  │
│  └── No longer requires separate Avid Link app             │
│                                                              │
│  Best Practices:                                             │
│  ├── Commit/freeze CPU-heavy tracks before uploading       │
│  ├── Communicate about who's editing what                  │
│  ├── Use track comments for notes                          │
│  ├── Upload frequently to avoid large syncs               │
│  └── Keep sessions organized with clear naming             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 12.5 Why Pro Tools is the Industry Standard

```
┌─────────────────────────────────────────────────────────────┐
│          ZAŠTO JE PRO TOOLS INDUSTRIJSKI STANDARD            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ISTORIJA I LEGACY:                                          │
│  ├── Pionir DAW-ova (1991, kao Sound Designer II)          │
│  ├── Prva ozbiljna non-linear audio workstation            │
│  ├── Installed base: 100,000+ professional studios        │
│  └── Generacije audio profesionalaca trained na PT         │
│                                                              │
│  POST-PRODUCTION DOMINACIJA:                                 │
│  ├── 90%+ Hollywood film/TV post koristi Pro Tools         │
│  ├── AAF/OMF workflow sa video editing softwarom           │
│  ├── Timecode sync i Video Satellite                       │
│  ├── Keyboard Focus za brzi editing                        │
│  └── Industry workflows built around Pro Tools             │
│                                                              │
│  RECORDING STUDIO STANDARD:                                  │
│  ├── HDX = Low latency tracking                            │
│  ├── Massive I/O support (256+ channels)                   │
│  ├── Rock-solid stability (DSP-based processing)           │
│  ├── Session compatibility across studios                  │
│  └── Client expectation: "We use Pro Tools"                │
│                                                              │
│  TEHNIČKE PREDNOSTI:                                         │
│  ├── Hybrid Engine (DSP + Native)                          │
│  ├── 64-bit mix bus summing                                │
│  ├── Automatic Delay Compensation                          │
│  ├── Dynamic Plugin Processing                             │
│  ├── Elastic Audio                                         │
│  ├── Beat Detective                                        │
│  └── Comprehensive EUCON control surface support           │
│                                                              │
│  WORKFLOW PREDNOSTI:                                         │
│  ├── Keyboard Commands Focus (JEDINSTVENO)                 │
│  ├── Edit modes (Shuffle/Slip/Spot/Grid)                   │
│  ├── Playlist-based comping                                │
│  ├── Window Configurations                                 │
│  ├── Memory Locations                                      │
│  └── Smart Tool                                            │
│                                                              │
│  ECOSYSTEM:                                                  │
│  ├── AAX plugin standard (kvalitetan QA)                   │
│  ├── Avid hardware integration                             │
│  ├── Cloud Collaboration                                   │
│  ├── Training/certification program                        │
│  └── Strong third-party support                            │
│                                                              │
│  KRITIKE (za balans):                                        │
│  ├── Subscription model (kontroverzno)                     │
│  ├── Nema native LUFS metering                             │
│  ├── MIDI historically weaker than competitors             │
│  ├── UI modernization slower than competitors              │
│  └── High entry cost (especially HDX)                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ZAKLJUČAK: Ključne Tačke za FluxForge Implementaciju

```
┌─────────────────────────────────────────────────────────────┐
│            FLUXFORGE IMPLEMENTATION PRIORITIES               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  KRITIČNO ZA KOPIRANJE:                                      │
│  ├── Keyboard Commands Focus Mode                          │
│  ├── Edit Modes (Shuffle/Slip/Spot/Grid)                   │
│  ├── Smart Tool behavior                                   │
│  ├── Playlist comping workflow                             │
│  ├── Insert architecture (10 slots, pre/post)              │
│  ├── Memory Locations system                               │
│  └── Window Configurations                                 │
│                                                              │
│  POBOLJŠANJA MOGUĆNOSTI (gde Pro Tools zaostaje):            │
│  ├── Native LUFS metering (PT nema)                        │
│  ├── Better MIDI workflow (PT istorijski slabiji)          │
│  ├── Modern UI (PT zaostaje)                               │
│  ├── Integrated spectral editing (PT nema)                 │
│  └── Better plugin browser (PT basic)                      │
│                                                              │
│  AUDIO ENGINE CILJEVI:                                       │
│  ├── 64-bit floating point mix bus                         │
│  ├── Ultra-low latency (< 3ms @ 128 samples)              │
│  ├── Automatic delay compensation                          │
│  ├── Dynamic plugin processing                             │
│  └── Lock-free audio thread (KRITIČNO)                     │
│                                                              │
│  MIXER ARCHITECTURE:                                         │
│  ├── Signal flow: Input → Clip Gain → Pre-Inserts →       │
│  │                Pre-Sends → Fader → Post-Inserts →       │
│  │                Post-Sends → Pan → Output                │
│  ├── 10 inserts (5 pre, 5 post)                           │
│  ├── 10 sends (5 pre, 5 post)                             │
│  ├── VCA functionality                                     │
│  └── Comprehensive bus routing                             │
│                                                              │
│  DSP PROCESOR TARGETS:                                       │
│  ├── 64-band EQ (PT ima 7-band max)                        │
│  ├── Linear phase opcija (PT nema)                         │
│  ├── Advanced dynamics (multiband, M/S)                    │
│  └── SIMD optimization (AVX-512/AVX2/SSE4.2/NEON)         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## IZVORI

- [Pro Tools 2024.10 Release Notes](https://www.avid.com/pro-tools/whats-new)
- [Production Expert - Pro Tools Coverage](https://www.production-expert.com/)
- [Sound On Sound - Pro Tools Techniques](https://www.soundonsound.com/techniques)
- [Pro Tools Reference Guide](https://resources.avid.com/SupportFiles/PT/)
- [Avid HDX Specifications](https://www.avid.com/products/pro-tools-hdx)
- [Pro Tools Training Resources](https://www.protoolstraining.com/)

---

**Dokument verzija:** 1.0
**Datum:** Januar 2026
**Autor:** FluxForge Studio Analysis
