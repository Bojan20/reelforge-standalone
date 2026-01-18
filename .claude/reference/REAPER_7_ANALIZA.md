# REAPER 7 — Kompletna Tehnička Analiza

**Verzija dokumenta:** 1.0
**Datum:** 2026-01-14
**Svrha:** Referentni dokument za implementaciju FluxForge Studio

---

## SADRŽAJ

1. [Audio Engine Arhitektura](#1-audio-engine-arhitektura)
2. [DSP Procesori (ReaPlugs)](#2-dsp-procesori-reaplugs)
3. [JSFX — Scripting DSP](#3-jsfx--scripting-dsp)
4. [Mixer Arhitektura](#4-mixer-arhitektura)
5. [Timeline/Arrangement](#5-timelinearrangement)
6. [Editing Mogućnosti](#6-editing-mogućnosti)
7. [Actions & Scripting](#7-actions--scripting)
8. [Plugin Hosting](#8-plugin-hosting)
9. [Project Management](#9-project-management)
10. [Metering & Visualization](#10-metering--visualization)
11. [UI/UX Design](#11-uiux-design)
12. [Jedinstvene Karakteristike](#12-jedinstvene-karakteristike)

---

## 1. AUDIO ENGINE ARHITEKTURA

### 1.1 Anticipative FX Processing (Revolucionarno!)

REAPER koristi **Anticipatory FX Processing** — jedinstven sistem koji omogućava maksimalno iskorišćenje CPU resursa.

```
┌─────────────────────────────────────────────────────────────────┐
│           ANTICIPATIVE FX PROCESSING ARHITEKTURA                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐              │
│   │  Core 1  │     │  Core 2  │     │  Core N  │              │
│   │ FX Chain │     │ FX Chain │     │ FX Chain │              │
│   └────┬─────┘     └────┬─────┘     └────┬─────┘              │
│        │                │                │                     │
│        ▼                ▼                ▼                     │
│   ┌─────────────────────────────────────────────────┐         │
│   │         RENDER-AHEAD BUFFER                     │         │
│   │   (Pre-procesira FX unapred kada je moguće)    │         │
│   └─────────────────────────────────────────────────┘         │
│                          │                                     │
│                          ▼                                     │
│   ┌─────────────────────────────────────────────────┐         │
│   │              AUDIO OUTPUT                        │         │
│   └─────────────────────────────────────────────────┘         │
│                                                                 │
│   PREDNOSTI:                                                    │
│   • Koristi ~100% dostupne CPU snage                           │
│   • Veći broj plugin-a nego drugi DAW-ovi                      │
│   • Niže UI latencije                                          │
│   • Cores rade nezavisno, retka sinhronizacija                 │
│                                                                 │
│   IZUZECI (koristi Synchronous FX Processing):                 │
│   • Live monitoring sa niskom latencijom                       │
│   • UAD DSP kartice                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Konfiguracija:**
1. `Preferences → Audio → Device` → Enable "Anticipative FX processing"
2. Set "Render-ahead" buffer size
3. Enable "Allow live FX-multiprocessing on X CPUs"
4. Per-track: Right-click → Track Performance Options → "Allow anticipative FX"

### 1.2 Sample Rates

| Sample Rate | Podržano | Napomena |
|-------------|----------|----------|
| 44.1 kHz | ✅ | Standard CD |
| 48 kHz | ✅ | Video standard |
| 88.2 kHz | ✅ | 2x CD |
| 96 kHz | ✅ | High-res audio |
| 176.4 kHz | ✅ | 4x CD |
| 192 kHz | ✅ | High-res mastering |
| 352.8 kHz | ✅ | DSD equivalent |
| 384 kHz | ✅ | Ultra high-res |
| **768 kHz** | ✅ | **Via per-FX oversampling!** |

**REAPER 7 uvodi per-FX i per-FX-chain oversampling** — bilo koji plugin može biti oversampled do 768 kHz!

### 1.3 Bit Depth

| Processing Stage | Bit Depth |
|-----------------|-----------|
| Internal processing | **64-bit floating point** |
| Plugin processing | 64-bit double precision |
| Metering | 64-bit |
| Export | 16/24/32-bit int, 32/64-bit float |

### 1.4 Buffer Sizes

| Buffer Size | Latencija @48kHz | Use Case |
|-------------|------------------|----------|
| 32 samples | 0.67 ms | Ultra-low latency recording |
| 64 samples | 1.33 ms | Professional tracking |
| 128 samples | 2.67 ms | **Optimalan balans** |
| 256 samples | 5.33 ms | Heavy plugin load |
| 512 samples | 10.67 ms | Mixing |
| 1024 samples | 21.33 ms | Mastering |
| 2048 samples | 42.67 ms | Offline processing |
| 4096 samples | 85.33 ms | Maximum stability |

### 1.5 Audio Device Handling

```
┌─────────────────────────────────────────────────────────────────┐
│                  AUDIO DRIVER SUPPORT                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  WINDOWS:                                                        │
│  ┌──────────────┬───────────────┬─────────────────────────────┐│
│  │ Driver       │ Latency       │ Notes                       ││
│  ├──────────────┼───────────────┼─────────────────────────────┤│
│  │ ASIO         │ Lowest (1ms)  │ Professional, exclusive     ││
│  │ WASAPI Excl. │ Very Low (2ms)│ No ASIO? Use this          ││
│  │ WASAPI Shared│ Low (5ms)     │ Multi-app audio            ││
│  │ DirectSound  │ High (20ms+)  │ Legacy, avoid              ││
│  │ WaveOut      │ Very High     │ Legacy, never use          ││
│  └──────────────┴───────────────┴─────────────────────────────┘│
│                                                                  │
│  macOS:                                                          │
│  ┌──────────────┬───────────────┬─────────────────────────────┐│
│  │ CoreAudio    │ Very Low (1ms)│ Native, excellent quality   ││
│  └──────────────┴───────────────┴─────────────────────────────┘│
│                                                                  │
│  Linux:                                                          │
│  ┌──────────────┬───────────────┬─────────────────────────────┐│
│  │ JACK         │ Very Low      │ Pro audio standard          ││
│  │ PipeWire     │ Low           │ Modern replacement          ││
│  │ ALSA         │ Medium        │ Direct hardware access      ││
│  │ PulseAudio   │ High          │ Desktop audio, avoid        ││
│  └──────────────┴───────────────┴─────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.6 Latency Compensation

**Automatic PDC (Plugin Delay Compensation):**
- REAPER automatski kompenzuje latenciju svih plugin-a
- Radi sa neograničenim brojem plugin-a u lancu
- Per-plugin manual offset za fine-tuning

**REAPER 7 dodaje:**
- Per-FX auto-bypass kada je input tih (silence detection)
- Customizable silence threshold
- Reduces CPU when tracks are silent

### 1.7 CPU Efficiency Optimizations

```
REAPER PERFORMANCE FEATURES:
├── Anticipative FX Processing
│   └── Pre-renders FX ahead of playback
├── Auto-suspend silent plugins
│   └── REAPER 7: Per-FX configurable
├── Thread priority settings
│   ├── Audio thread: Time Critical
│   ├── Worker threads: Highest
│   └── UI thread: Normal
├── Media buffering
│   └── Per-track configurable
├── FX tail handling
│   └── Smart FX disable without cutting tails
└── Performance meter
    └── Real-time CPU/memory monitoring
```

---

## 2. DSP PROCESORI (ReaPlugs)

### 2.1 ReaEQ — Parametric Equalizer

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Broj bendova | **NEOGRANIČENO** |
| Filter tipovi | 7 (Low Pass, High Pass, Low Shelf, High Shelf, Band, Bandpass, Notch) |
| Internal precision | 64-bit double |
| Frequency range | 20 Hz – 20 kHz+ |
| Gain range | ±∞ dB |
| Q range | 0.01 – 100+ |

**FUNKCIJE:**
```
ReaEQ FEATURES:
├── Unlimited EQ bands
├── Real-time FFT analyzer
│   ├── Shows input signal spectrum
│   └── Optional phase response display
├── Note/octave display
│   └── Shows musical note for each frequency
├── Mouse modifiers
│   ├── Drag: Frequency
│   ├── Ctrl+Drag: Gain
│   └── Shift+Drag: Q/Bandwidth
├── Completely transparent
│   └── Zero coloration, surgical EQ
└── CPU-efficient
    └── Negligible CPU even with many bands
```

**FILTER TIPOVI:**
1. **Low Pass** — Atenuira frekvencije iznad cutoff-a
2. **High Pass** — Atenuira frekvencije ispod cutoff-a
3. **Low Shelf** — Boost/cut ispod cutoff-a
4. **High Shelf** — Boost/cut iznad cutoff-a
5. **Band (Bell)** — Parametric boost/cut
6. **Bandpass** — Propušta samo odabrani opseg
7. **Notch** — Uklanja usku frekvenciju

### 2.2 ReaComp — Compressor

**SPECIFIKACIJE:**

| Parameter | Range | Default |
|-----------|-------|---------|
| Threshold | −60 dB to 0 dB | −20 dB |
| Ratio | 1:1 to ∞:1 | 4:1 |
| Attack | **0 ms** to 500 ms | 3 ms |
| Release | **0 ms** to 5000 ms | 100 ms |
| Knee | Hard to Soft | — |
| Pre-comp | 0–50 ms look-ahead | 0 |

**FUNKCIJE:**
```
ReaComp FEATURES:
├── Ultra-fast attack (0ms!)
├── Program-dependent release
├── Comprehensive sidechain
│   ├── Main stereo input
│   ├── Left channel only
│   ├── Right channel only
│   └── External sidechain input
├── Sidechain filtering
│   ├── High-pass filter
│   └── Low-pass filter
├── Parallel compression
│   ├── Wet slider
│   └── Dry slider (NY compression)
├── RMS/Peak detection
│   └── Configurable RMS window
├── Feedback/Feedforward modes
└── Full metering
    ├── Input level
    ├── Output level
    └── Gain reduction
```

### 2.3 ReaXcomp — Multiband Compressor

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Broj bendova | **NEOGRANIČENO** |
| Crossover slope | Configurable |
| Per-band controls | Full compressor per band |

**PER-BAND KONTROLE:**
- Threshold
- Ratio (uključujući < 1:1 za expander!)
- Knee
- Attack
- Release
- Makeup gain
- Program-dependent release
- Feedback detector
- RMS size
- Solo band mode

```
ReaXcomp ARHITEKTURA:
┌─────────────────────────────────────────────────────────────────┐
│                         INPUT                                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
    ┌───────────┐   ┌───────────┐   ┌───────────┐
    │  Band 1   │   │  Band 2   │   │  Band N   │
    │ (Low)     │   │ (Mid)     │   │ (High)    │
    │           │   │           │   │           │
    │ Compressor│   │ Compressor│   │ Compressor│
    │ or        │   │ or        │   │ or        │
    │ Expander  │   │ Expander  │   │ Expander  │
    └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
          │               │               │
          └───────────────┼───────────────┘
                          ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                        OUTPUT                                │
    └─────────────────────────────────────────────────────────────┘
```

### 2.4 ReaLimit — Brickwall Limiter

**SPECIFIKACIJE (REAPER 7 novi plugin!):**

| Feature | Vrednost |
|---------|----------|
| Type | Brickwall limiter / Loudness maximizer |
| Look-ahead modes | Multiple |
| Ceiling | Configurable |
| Visual display | Peak visualization |
| Sound character | Clean, transparent |

### 2.5 ReaGate — Noise Gate

**SPECIFIKACIJE:**

| Parameter | Range |
|-----------|-------|
| Threshold | −96 dB to 0 dB |
| Attack | 0 ms to 500 ms |
| Hold | 0 ms to 5000 ms |
| Release | 0 ms to 5000 ms |
| Pre-open (look-ahead) | 0 ms to 50 ms |
| Hysteresis | Configurable |

**JEDINSTVENE FUNKCIJE:**
```
ReaGate SPECIAL FEATURES:
├── External sidechain support
├── Hysteresis control
│   └── Prevents gate flutter
├── Pre-open (look-ahead)
│   └── Catches transients before they're cut
├── MIDI output!
│   └── Outputs MIDI note when gate opens
│   └── PERFECT for drum replacement
├── White noise output option
└── Full metering
```

### 2.6 ReaDelay — Multi-tap Delay

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Broj tap-ova | **NEOGRANIČENO** |
| Delay time | ms ili musical divisions |
| Per-tap filtering | High-pass + Low-pass |
| Per-tap pan | Full stereo control |
| Stereo width | Per-tap control |
| Resolution | Bit-crush effect |

```
ReaDelay TAP STRUKTURA:
┌─────────────────────────────────────────────────────────────────┐
│  TAP 1                                                          │
│  ├── Delay: 250ms (1/4 note)                                   │
│  ├── Volume: -6dB                                               │
│  ├── Pan: Center                                                │
│  ├── HP Filter: 200Hz                                           │
│  ├── LP Filter: 8kHz                                            │
│  ├── Width: 100%                                                │
│  └── Resolution: Full                                           │
├─────────────────────────────────────────────────────────────────┤
│  TAP 2                                                          │
│  ├── Delay: 500ms (1/2 note)                                   │
│  ├── Volume: -12dB                                              │
│  ├── Pan: Left 50%                                              │
│  └── ...                                                        │
├─────────────────────────────────────────────────────────────────┤
│  TAP N...                                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 2.7 ReaVerb — Convolution Reverb

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Type | FFT Convolution + Synthetic IR |
| IR formats | WAV, AIFF |
| FFT size | Configurable (affects latency) |
| Zero-latency mode | ✅ Available |
| IR manipulation | Trim, Gain, Stretch |
| Built-in modules | Echo Generator, Reverb Generator, Filter, Normalize |

**MODULI:**
```
ReaVerb PROCESSING CHAIN:
┌─────────────────────────────────────────────────────────────────┐
│                         INPUT                                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  MODULE 1: File/IR Loader                                    │
    │  • Load WAV/AIFF impulse response                           │
    │  • Trim/Gain/Stretch controls                               │
    │  • Normalize to -18dBFS                                      │
    └───────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  MODULE 2: Reverb Generator (Synthetic)                      │
    │  • Create IR algorithmically                                │
    │  • Room size, decay, diffusion                              │
    └───────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  MODULE 3: Echo Generator                                    │
    │  • Add discrete echoes                                       │
    └───────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  MODULE 4: Filter                                            │
    │  • Shape reverb frequency response                          │
    └───────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │  CONVOLUTION ENGINE (FFT)                                    │
    │  • Zero-latency option                                       │
    │  • Extra thread for low-latency performance                 │
    └───────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                        OUTPUT                                │
    └─────────────────────────────────────────────────────────────┘
```

**NAPOMENA:** Nema uključene IR-ove — dostupni besplatno online (OpenAIR, Fokus, itd.)

### 2.8 ReaFIR — FFT-based Processor

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| FFT sizes | 128 to 32768 |
| Modes | EQ, Gate, Compressor, Convolve L/R, **Subtract** |
| Curve editing | Points or freehand |
| Artifacts reduction | FIR filter mode |

**MODOVI:**

1. **EQ Mode** — Precision FFT EQ, freehand curve drawing
2. **Gate Mode** — FFT-based noise gate
3. **Compressor Mode** — FFT-based dynamics
4. **Convolve L/R** — Cross-convolve stereo channels
5. **Subtract Mode** — **NOISE REMOVAL!**

**SUBTRACT MODE (Noise Removal):**
```
REAFIR NOISE REMOVAL WORKFLOW:
1. Enable "Subtract" mode
2. Check "Automatically build noise profile"
3. Play section with ONLY noise (no signal)
4. Uncheck "Automatically build noise profile"
5. Noise profile is captured → all matching frequencies removed
6. Adjust profile level with Ctrl+drag if artifacts occur

BEST FOR:
• Steady-state noise (hum, fan, AC)
• NOT for transient/random noise
```

### 2.9 ReaTune — Pitch Correction

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Modes | Tuner, Automatic, Manual |
| Scales | Major, Minor, Chromatic, Dorian, Phrygian, Lydian, Mixolydian, Locrian, Arabian, Egyptian |
| Algorithms | Simple windowed, elastique 2.1 pro/efficient/SOLO |
| Real-time analysis | ✅ With graphical display |

**MODOVI:**
```
ReaTune MODES:
├── Tuner Mode
│   └── Real-time pitch display, instrument tuner
├── Automatic Pitch Correction
│   ├── Set target scale
│   ├── Set correction speed
│   └── Auto-corrects to nearest scale note
└── Manual Pitch Correction
    ├── Visual pitch envelope editor
    ├── Draw desired pitch
    └── Sample-accurate editing
```

### 2.10 ReaPitch — Pitch Shifter

**SPECIFIKACIJE:**

| Parameter | Range |
|-----------|-------|
| Pitch shift | ±octaves |
| Formant shift | ±semitones/cents |
| Shifters | Multiple (parallel pitch shifting) |
| Per-shifter panning | ✅ |

**USE CASES:**
- Vocal harmonies
- Instrument doubling
- Sound design
- Formant manipulation

### 2.11 ReaVoice — MIDI-Controlled Pitch Shifter

- Pitch shift controlled by MIDI input
- Multi-voice capable
- Real-time MIDI control

### 2.12 ReaVocode — Vocoder

**KONTROLE:**
- Wet/Dry detector mix
- Wet/Dry modulator mix
- Number of frequency bands
- Swap detector/modulator toggle
- Stereo enable

### 2.13 ReaSamplOmatic5000 — Sampler

**SPECIFIKACIJE:**

| Feature | Vrednost |
|---------|----------|
| Sample formats | WAV, AIFF, MP3, etc. |
| Note range | Configurable min/max |
| Velocity layers | ✅ |
| Round-robin | ✅ |
| MIDI choke | Via JS:MIDI Choke |

**DRUM MACHINE SETUP:**
```
DRUM MACHINE ARHITEKTURA:
┌─────────────────────────────────────────────────────────────────┐
│  TRACK 1: Kick                                                   │
│  ├── ReaSamplOmatic5000                                         │
│  ├── Sample: kick.wav                                           │
│  └── Note range: C1 only                                         │
├─────────────────────────────────────────────────────────────────┤
│  TRACK 2: Snare                                                  │
│  ├── ReaSamplOmatic5000                                         │
│  ├── Sample: snare.wav                                          │
│  └── Note range: D1 only                                         │
├─────────────────────────────────────────────────────────────────┤
│  TRACK 3: Hi-Hat Closed                                          │
│  ├── ReaSamplOmatic5000                                         │
│  ├── Sample: hihat_closed.wav                                   │
│  ├── Note range: F#1 only                                        │
│  └── Obey note-offs: TRUE (for choke)                           │
├─────────────────────────────────────────────────────────────────┤
│  TRACK 4: Hi-Hat Open                                            │
│  ├── ReaSamplOmatic5000                                         │
│  ├── Sample: hihat_open.wav                                     │
│  ├── Note range: A#1 only                                        │
│  └── JS: MIDI Choke → chokes on F#1                             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.14 ReaSynth & ReaSynDr

**ReaSynth:**
- Basic synthesizer
- Waveform: Sine, Square, Saw, Triangle
- ADSR Envelope
- Portamento

**ReaSynDr:**
- 4 drum samples: Kick, Snare, Blip, Tick
- Quick drum sounds without external samples

---

## 3. JSFX — SCRIPTING DSP

### 3.1 Pregled

**JSFX je JEDINSTVENA karakteristika REAPER-a** — omogućava pisanje custom DSP plugin-a u EEL2 jeziku koji se kompajlira u realnom vremenu.

```
JSFX KARAKTERISTIKE:
├── Jezik: EEL2 (sličan C-u)
├── Kompilacija: Real-time (edit → instant reload)
├── Performance: Blizu nativnog koda
├── Sample-accurate: Kod se izvršava per-sample
├── GUI: Custom vector grafika
├── MIDI: Potpuna MIDI obrada
├── Format: Plain text files (.jsfx)
└── Open Source: Od juna 2025!
```

### 3.2 EEL2 Jezik

**Karakteristike:**
```c
// EEL2 BASICS:
// - Varijable ne zahtevaju deklaraciju
// - Sve varijable su double (64-bit float)
// - Case-insensitive (a == A)
// - Max variable name: 127 karaktera

// Konstante:
$pi    // 3.14159...
$phi   // 1.618... (golden ratio)
$e     // 2.718... (Euler's number)

// Operatori:
+ - * / ^          // Arithmetic
| & ~ << >>        // Bitwise
< <= > >= == !=    // Comparison
```

### 3.3 Kod Sekcije

```c
// ═══════════════════════════════════════════════════════════════
// @INIT — Inicijalizacija (load, samplerate change, playback start)
// ═══════════════════════════════════════════════════════════════
@init
// Memorija je zero na load
buffer_size = 1024;
buffer = 0;  // Alociraj buffer na adresi 0

// ═══════════════════════════════════════════════════════════════
// @SLIDER — Slider promene
// ═══════════════════════════════════════════════════════════════
slider1:0<-60,0,0.1>Gain (dB)
slider2:1000<20,20000,1>Frequency (Hz)

@slider
gain = 10^(slider1/20);  // dB to linear
freq = slider2;

// ═══════════════════════════════════════════════════════════════
// @BLOCK — Pre-sample-loop processing (once per buffer)
// ═══════════════════════════════════════════════════════════════
@block
// samplesblock = number of samples in this block

// ═══════════════════════════════════════════════════════════════
// @SAMPLE — Per-sample processing (AUDIO THREAD!)
// ═══════════════════════════════════════════════════════════════
@sample
spl0 *= gain;  // Left channel
spl1 *= gain;  // Right channel

// ═══════════════════════════════════════════════════════════════
// @GFX — Custom GUI drawing
// ═══════════════════════════════════════════════════════════════
@gfx 400 300  // Window size
gfx_clear = 0x1a1a20;  // Background color
gfx_r = 0.3; gfx_g = 0.6; gfx_b = 1.0;  // Blue
gfx_circle(gfx_w/2, gfx_h/2, 50, 1);    // Filled circle
```

### 3.4 Shared Memory (gmem[])

```c
// Globalna memorija deljenja između JSFX instanci
// ~1 million words available

// Instance 1: Pošalji vrednost
@sample
gmem[0] = spl0;  // Share left channel

// Instance 2: Primi vrednost
@sample
received = gmem[0];  // Read from other instance
```

### 3.5 Ugrađeni JSFX Plugin-i

REAPER dolazi sa **stotinama** JSFX plugin-a:

```
JSFX KATEGORIJE:
├── Analysis
│   ├── Spectrum analyzers
│   ├── Phase correlation
│   └── Loudness meters
├── Delay
│   ├── Basic delay
│   ├── Ping-pong
│   └── Multi-tap
├── Distortion
│   ├── Saturation
│   ├── Tube simulation
│   └── Bit crusher
├── Dynamics
│   ├── Compressors
│   ├── Limiters
│   └── Gates
├── EQ
│   ├── Graphic EQ
│   ├── Parametric
│   └── Shelving
├── Filter
│   ├── Low-pass
│   ├── High-pass
│   ├── Bandpass
│   └── Formant
├── Modulation
│   ├── Chorus
│   ├── Flanger
│   ├── Phaser
│   └── Tremolo
├── Pitch
│   ├── Pitch shifter
│   └── Harmonizer
├── Reverb
│   ├── Algorithmic
│   └── Plate simulation
├── Utility
│   ├── Gain
│   ├── Pan
│   ├── Mid/Side
│   └── Stereo width
└── MIDI
    ├── MIDI filter
    ├── MIDI transpose
    └── MIDI choke
```

### 3.6 CookDSP Library

Eksterni DSP library za JSFX razvoj — uključuje:
- Oscillators
- Filters
- Delays
- Granular processing
- FFT tools

---

## 4. MIXER ARHITEKTURA

### 4.1 Revolutionary Track Concept

**U REAPER-u: Track = Bus = Folder = Send = AUX = VCA**

```
REAPER TRACK FILOZOFIJA:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   "U REAPER-u postoji samo TRACK."                              │
│                                                                  │
│   Track može biti:                                               │
│   • Audio track                                                  │
│   • MIDI track                                                   │
│   • Video track                                                  │
│   • Bus/Aux                                                      │
│   • Folder (submix)                                              │
│   • Send destination                                             │
│   • VCA master                                                   │
│   • Bilo koja kombinacija!                                       │
│                                                                  │
│   NEMA posebnih tipova track-ova!                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Channel Count

| Version | Channels per Track |
|---------|-------------------|
| REAPER 6 | 64 channels |
| **REAPER 7** | **128 channels** |

**Svaki track je 128-kanalni DAW!**

### 4.3 Routing Matrix

```
REAPER ROUTING MOGUĆNOSTI:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   TRACK 1 ──┬──► Hardware Out 1-2                               │
│             ├──► Track 5 (Bus) Ch 1-2                           │
│             ├──► Track 6 (Reverb Send) Ch 1-2                   │
│             └──► Track 7 Sidechain Input Ch 3-4                 │
│                                                                  │
│   Svaki track može rutirati na:                                 │
│   • Bilo koji hardware output                                   │
│   • Bilo koji drugi track                                       │
│   • Bilo koji channel tog track-a                               │
│   • Parent folder track                                         │
│   • Master                                                       │
│   • Nigde (no output)                                           │
│                                                                  │
│   Routing je:                                                    │
│   • NEOGRANIČEN broj sends                                      │
│   • NEOGRANIČEN broj receives                                   │
│   • Per-channel volume/pan                                       │
│   • Pre/Post FX/Fader options                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.4 Folder Tracks (Submixes)

```
FOLDER TRACK ARHITEKTURA:
┌─────────────────────────────────────────────────────────────────┐
│  📁 DRUMS (Folder)                                               │
│  ├── 🎵 Kick                                                     │
│  ├── 🎵 Snare                                                    │
│  ├── 🎵 Toms                                                     │
│  └── 🎵 Overheads                                                │
│                                                                  │
│  Audio od child tracks automatski ide na folder track           │
│  Folder track = Submix bus                                       │
│  FX na folder track = Bus processing                            │
│                                                                  │
│  Folder može biti nested u drugi folder:                        │
│  📁 ALL INSTRUMENTS                                              │
│  ├── 📁 DRUMS                                                    │
│  │   ├── 🎵 Kick                                                │
│  │   └── ...                                                    │
│  ├── 📁 BASS                                                     │
│  └── 📁 GUITARS                                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.5 FX Containers (REAPER 7)

**Novo u REAPER 7:**

```
FX CONTAINERS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   FX Container = Self-contained FX chain sa:                    │
│   • Kompleksnim routing-om                                       │
│   • Parameter mappings                                           │
│   • Recall/Save kao jedan "plugin"                              │
│                                                                  │
│   PRIMER - Parallel Compression Container:                       │
│   ┌───────────────────────────────────────────┐                 │
│   │  FX Container: "NYC Compression"          │                 │
│   │  ┌─────────────────────────────────────┐ │                 │
│   │  │         INPUT                       │ │                 │
│   │  └─────────────┬───────────────────────┘ │                 │
│   │          ┌─────┴─────┐                    │                 │
│   │          ▼           ▼                    │                 │
│   │    ┌──────────┐ ┌──────────┐             │                 │
│   │    │  DRY     │ │ COMPRESS │             │                 │
│   │    │  Path    │ │ Heavy    │             │                 │
│   │    └────┬─────┘ └────┬─────┘             │                 │
│   │         │            │                    │                 │
│   │         └──────┬─────┘                    │                 │
│   │                ▼                          │                 │
│   │         ┌──────────┐                      │                 │
│   │         │   MIX    │                      │                 │
│   │         └──────────┘                      │                 │
│   └───────────────────────────────────────────┘                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.6 Parallel FX Routing (REAPER 7)

```
PARALLEL FX:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   FX CHAIN:                                                      │
│   1. ReaEQ                                                       │
│   2. ReaComp          ║                                          │
│   3. ReaDelay         ║  ← Parallel (označeno sa ║)             │
│   4. ReaVerb          ║                                          │
│   5. ReaLimit                                                    │
│                                                                  │
│   Right-click FX → "Run selected FX in parallel with previous"  │
│                                                                  │
│   FLOW:                                                          │
│   ReaEQ ──┬──► ReaComp  ──┐                                     │
│           ├──► ReaDelay ──┼──► Mix ──► ReaLimit                 │
│           └──► ReaVerb  ──┘                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.7 Hardware Outputs

```
HARDWARE ROUTING:
├── Unlimited hardware outputs
├── Per-output channel mapping
├── Per-output volume/pan
├── Multiple audio device support (via ASIO multi-client)
└── ReWire support (master/slave)
```

---

## 5. TIMELINE/ARRANGEMENT

### 5.1 Track Lanes (REAPER 7)

**Fixed-lane tracks** — nova funkcija u REAPER 7:

```
FIXED LANES:
┌─────────────────────────────────────────────────────────────────┐
│  TRACK: Vocal                                                    │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Lane 1: Take 1 [=========|        |====]                  │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ Lane 2: Take 2 [    |=========|        ]    ← selected   │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │ Lane 3: Take 3 [        |    |========]                   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                  │
│  FEATURES:                                                       │
│  • Record overlapping media to separate lanes                   │
│  • Per-lane playback enable/disable                             │
│  • Swipe comping across lanes                                   │
│  • Automatic lane management                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Takes & Comping

```
COMPING WORKFLOW (REAPER 7 Swipe Comping):
1. Record multiple takes na isti track
2. Takes se automatski slažu u lanes
3. SWIPE preko željenih sekcija da odabereš beste
4. Automatski crossfades na granicama
5. Comp Pool: Sačuvaj različite kombinacije

COMP POOL:
├── Comp A: Verse 1 from Take 2, Chorus from Take 3...
├── Comp B: All from Take 1 except...
└── Comp C: Custom combination
```

### 5.3 Item Types

```
ITEM TYPES:
├── Audio items
│   ├── WAV, AIFF, FLAC, MP3, OGG, etc.
│   └── REX2 files (beat slices)
├── MIDI items
│   ├── .mid files
│   └── REAPER native MIDI
├── Video items
│   ├── AVI, MOV, MP4, WMV
│   └── Via FFmpeg
├── Empty items
│   └── Placeholders
├── Subproject items
│   └── .RPP nested projects
└── Pooled items
    └── Shared source media
```

### 5.4 Item Properties

```
ITEM PROPERTIES (F2 ili double-click):
├── Position & Length
│   ├── Position (timeline)
│   ├── Length
│   └── Snap offset
├── Fades
│   ├── Fade in length
│   ├── Fade out length
│   ├── Fade curve type (7+ types)
│   └── Auto-crossfade settings
├── Time Stretch
│   ├── Playback rate
│   ├── Pitch adjust (semitones)
│   ├── Preserve pitch when changing rate
│   └── Time stretch mode (elastique, etc.)
├── Take Properties
│   ├── Volume
│   ├── Pan
│   ├── Pitch (+/- semitones)
│   └── Start offset
└── Display
    ├── Color
    ├── Opacity
    ├── Show peaks/MIDI
    └── Item name
```

### 5.5 Fades & Crossfades

```
FADE TYPES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Linear:        ╱                                               │
│                                                                  │
│  Fast Start:    ╱‾                                              │
│                                                                  │
│  Fast End:     _╱                                               │
│                                                                  │
│  Slow S/E:    _╱‾                                               │
│                                                                  │
│  S-Curve:     _╱‾ (smooth)                                      │
│                                                                  │
│  + Custom bezier curves                                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

CROSSFADE:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   Item 1      ╲                                                 │
│                ╲╱                                                │
│   Item 2        ╱                                               │
│                                                                  │
│  Auto-crossfade na overlap                                      │
│  Configurable default crossfade time                            │
│  Per-crossfade shape editing                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.6 Stretch Markers

```
STRETCH MARKERS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ITEM: [====|====|====|====|====]                               │
│            ↑    ↑    ↑    ↑                                     │
│         Stretch markers                                          │
│                                                                  │
│  Drag marker = time stretch that section                        │
│  Used for:                                                       │
│  • Tempo matching                                                │
│  • Drum quantization                                             │
│  • Vocal timing correction                                       │
│  • Sound design                                                  │
│                                                                  │
│  DYNAMIC SPLIT → Add stretch markers at transients              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.7 Automation

```
AUTOMATION MODES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  TRIM/READ (Default):                                            │
│  • Envelope controls parameter                                   │
│  • Fader controls offset (trim)                                 │
│  • Best of both worlds!                                          │
│                                                                  │
│  READ:                                                           │
│  • Envelope fully controls parameter                            │
│  • Fader follows envelope                                        │
│                                                                  │
│  WRITE:                                                          │
│  • Always recording automation                                   │
│  • Overwrites existing                                           │
│  • ⚠️ OPREZ — uvek piše!                                        │
│                                                                  │
│  TOUCH:                                                          │
│  • Records only while adjusting                                  │
│  • Stops when you release                                        │
│  • Least destructive                                             │
│                                                                  │
│  LATCH:                                                          │
│  • Records when you start adjusting                              │
│  • Continues until playback stops                                │
│  • Holds last value                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

AUTOMATABLE PARAMETERS:
├── Volume (Pre-FX, Post-Fader)
├── Pan (Pre-FX, Post-Fader)
├── Width
├── Trim Volume
├── Mute
├── ANY plugin parameter!
└── MIDI CC
```

### 5.8 Time Selection

```
TIME SELECTION:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Timeline: |----[========]--------------|                       │
│                    ↑                                            │
│             Time selection                                       │
│                                                                  │
│  USES:                                                           │
│  • Loop playback                                                 │
│  • Render bounds                                                 │
│  • Crop to time selection                                       │
│  • Insert empty space                                            │
│  • Remove time                                                   │
│  • Apply action to selection                                     │
│                                                                  │
│  SHORTCUT: Click-drag on ruler                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.9 Markers & Regions

```
MARKERS & REGIONS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  MARKERS (single point):                                         │
│  |      M1        M2              M3              M4            │
│         ↓         ↓               ↓               ↓             │
│  |------●---------●---------------●---------------●------|      │
│       "Intro"  "Verse"        "Chorus"        "Bridge"          │
│                                                                  │
│  Shortcut: M                                                     │
│  Jump to marker: 1-0 keys                                        │
│                                                                  │
│  ───────────────────────────────────────────────────────────    │
│                                                                  │
│  REGIONS (span):                                                 │
│  |---[=====VERSE 1=====]--[===CHORUS===]--[=VERSE 2=]---|       │
│                                                                  │
│  Shortcut: Shift+R (create from time selection)                 │
│  Uses:                                                           │
│  • Render to files (each region = file)                         │
│  • Region Playlists                                              │
│  • Arrangement markers                                           │
│  • Chapter markers (for video)                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.10 Project Tabs

**REAPER podržava multiple projekata istovremeno:**

```
PROJECT TABS:
┌─────────────────────────────────────────────────────────────────┐
│  [Project A.RPP] [Project B.RPP] [Untitled] [+]                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FEATURES:                                                       │
│  • Svaki tab = nezavisan projekat                               │
│  • Copy/paste između projekata                                   │
│  • Različiti sample rates po projektu                           │
│  • Share resources (plugins, media)                              │
│  • Quick A/B comparison                                          │
│                                                                  │
│  SUBPROJECTS:                                                    │
│  • Drag .RPP fajl na timeline                                   │
│  • Postaje "item" sa renderovanim audio-om                      │
│  • Double-click = otvori subproject tab                         │
│  • Save subproject = auto re-render                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. EDITING MOGUĆNOSTI

### 6.1 Item Editing

```
BASIC ITEM EDITING:
├── Split: S
├── Heal split: H
├── Delete: Delete
├── Duplicate: Ctrl+D
├── Copy/Paste: Ctrl+C/V
├── Move: Drag
├── Resize: Drag edges
├── Slip edit: Alt+Drag
├── Fade in/out: Drag corners
├── Crossfade: Overlap items
└── Reverse: Right-click → Reverse
```

### 6.2 MIDI Editing

```
MIDI EDITOR:
┌─────────────────────────────────────────────────────────────────┐
│  ┌──────┬────────────────────────────────────────────────────┐ │
│  │ C5   │                                                    │ │
│  │ B4   │        ▬▬▬                                        │ │
│  │ A4   │    ▬▬▬▬▬▬▬▬                                       │ │
│  │ G4   │                    ▬▬▬▬                           │ │
│  │ F4   │  ▬▬                                               │ │
│  │ E4   │                                                    │ │
│  │ D4   │                              ▬▬▬▬▬▬               │ │
│  │ C4   │                                                    │ │
│  └──────┴────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ VELOCITY  ║   ║  ║ ║   ║   ║║ ║                          ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  VIEWS:                                                          │
│  • Piano roll (default)                                          │
│  • Drum mode (diamonds/triangles)                               │
│  • Event list                                                    │
│  • Notation (via third-party)                                   │
│                                                                  │
│  STEP RECORDING:                                                 │
│  1. Enable step input mode                                       │
│  2. Play notes on MIDI keyboard                                  │
│  3. Notes inserted at cursor, cursor advances                   │
│  4. Grid controls note duration                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Razor Editing (REAPER 7)

```
RAZOR EDITING:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  STANDARD EDITING:                                               │
│  Select item → Edit item                                         │
│                                                                  │
│  RAZOR EDITING:                                                  │
│  Draw selection → Edit ONLY that area                           │
│                                                                  │
│  Timeline: |=====[///RAZOR EDIT///]=====|                       │
│                                                                  │
│  FEATURES:                                                       │
│  • Select across multiple tracks                                 │
│  • Cut through items without splitting                          │
│  • Copy/paste razor selections                                  │
│  • Stretch by dragging edges                                    │
│  • Include/exclude automation                                   │
│  • Independent of item boundaries                                │
│                                                                  │
│  ACTIONS:                                                        │
│  • Delete content                                                │
│  • Move content                                                  │
│  • Copy content                                                  │
│  • Stretch content                                               │
│  • Apply FX to selection                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 Dynamic Split

```
DYNAMIC SPLIT:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  PURPOSE: Split audio based on transients/threshold             │
│                                                                  │
│  ACCESS: Item → Item Processing → Dynamic Split Items (D)       │
│                                                                  │
│  OPTIONS:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Split Points:                                            │   │
│  │ ☑ At transients                                          │   │
│  │ □ When gate opens                                        │   │
│  │ □ When gate closes                                       │   │
│  │                                                           │   │
│  │ Transient sensitivity: [████████░░░░░░]                  │   │
│  │ Min slice length: 20 ms                                  │   │
│  │ Reduce splits: [░░░░░░░░░░░░░░░]                         │   │
│  │                                                           │   │
│  │ Actions:                                                  │   │
│  │ ○ Split selected items                                   │   │
│  │ ○ Add stretch markers at transients                      │   │
│  │ ○ Add take markers                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  USE CASES:                                                      │
│  • Drum editing/quantization                                    │
│  • Beat slicing                                                  │
│  • Sample creation                                               │
│  • Tempo detection                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.5 Transient Detection

```
TRANSIENT DETECTION:
├── Automatic detection based on:
│   ├── RMS level changes
│   ├── Threshold settings
│   └── Attack characteristics
├── Sensitivity adjustment
├── WAV/AIFF embedded transient support
├── REX file beat slice import
└── Actions:
    ├── Add transient guides
    ├── Add stretch markers at transients
    └── Dynamic split at transients
```

### 6.6 Batch Processing

```
BATCH PROCESSING OPTIONS:
├── Item batch processing
│   └── Apply FX chain to multiple items
├── File batch convert
│   └── Via render dialog
├── Region render
│   └── Each region → separate file
├── ReaScript batch processing
│   └── Custom scripts for mass edits
└── SWS: Batch processing actions
```

---

## 7. ACTIONS & SCRIPTING

### 7.1 Actions System

**REAPER ima preko 3000+ built-in actions** + SWS dodaje još 1000+

```
ACTIONS SYSTEM:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ACCESS: Actions → Show action list (Shift+?)                   │
│                                                                  │
│  SECTIONS:                                                       │
│  ├── Main                                                        │
│  ├── Main (alt recording)                                       │
│  ├── MIDI Editor                                                 │
│  ├── MIDI Event List Editor                                      │
│  ├── MIDI Inline Editor                                          │
│  ├── Media Explorer                                              │
│  └── Others...                                                   │
│                                                                  │
│  ASSIGNABLE TO:                                                  │
│  ├── Keyboard shortcuts                                          │
│  ├── Mouse modifiers                                             │
│  ├── MIDI notes/CC                                               │
│  ├── Toolbar buttons                                             │
│  ├── Menus                                                       │
│  └── OSC                                                         │
│                                                                  │
│  FILTER:                                                         │
│  Polje za pretragu — type anything to find actions              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Custom Actions (Macros)

```
CUSTOM ACTIONS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  CREATION:                                                       │
│  Actions → Show action list → New action → New custom action    │
│                                                                  │
│  PRIMER — "Insert Track with EQ":                               │
│  1. Track: Insert new track                                      │
│  2. Track: Insert virtual instrument on new track               │
│  3. FX: Add FX → ReaEQ                                          │
│                                                                  │
│  PRIMER — "Bounce in Place":                                    │
│  1. Item: Select all items on selected tracks                   │
│  2. Item: Render items as new take                              │
│  3. Take: Crop to active take                                   │
│  4. Item: Remove source media files                             │
│                                                                  │
│  NEOGRANIČENO akcija u jednom custom action-u!                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.3 ReaScript (Lua, EEL2, Python)

```
REASCRIPT LANGUAGES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  LUA (RECOMMENDED):                                              │
│  ├── Embedded in REAPER (no install)                            │
│  ├── Lua 5.4                                                     │
│  ├── Best balance of features/simplicity                        │
│  ├── Full GUI support                                            │
│  └── Huge community script library                               │
│                                                                  │
│  EEL2:                                                           │
│  ├── Embedded in REAPER                                          │
│  ├── Same as JSFX language                                       │
│  ├── Full GUI support                                            │
│  ├── Fast performance                                            │
│  └── Also used in video processor                                │
│                                                                  │
│  PYTHON:                                                         │
│  ├── Requires separate installation                              │
│  ├── Python 2.7 – 3.x supported                                 │
│  ├── NO GUI support in REAPER                                   │
│  ├── Slower than Lua/EEL                                        │
│  └── Access to Python ecosystem                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Lua primer:**
```lua
-- Get selected track
local track = reaper.GetSelectedTrack(0, 0)
if track then
    -- Get track name
    local _, name = reaper.GetTrackName(track)
    -- Show message
    reaper.ShowMessageBox("Selected: " .. name, "Info", 0)
    -- Set volume to -6dB
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", 0.5) -- 0.5 = -6dB
end
```

### 7.4 SWS Extensions

**SWS = "S&M, White Tie, Schwa" — community extension package**

```
SWS FEATURES:
├── ADDITIONAL ACTIONS (1000+)
│   ├── Advanced item manipulation
│   ├── Track management
│   ├── Envelope tools
│   └── MIDI tools
├── CYCLE ACTION EDITOR
│   ├── Create multi-state toggle actions
│   ├── Step through options with single key
│   └── Custom logic (if/then)
├── REGION PLAYLIST
│   ├── Playlist of regions
│   ├── Non-linear playback order
│   └── Export to new project
├── SNAPSHOTS
│   └── Save/recall mixer states
├── AUTO COLOR
│   └── Automatic track coloring
├── MARKER ACTIONS
│   └── Execute actions at markers
├── LIVE CONFIGS
│   └── Live performance setups
└── GROOVES
    └── Timing templates
```

### 7.5 Cycle Actions

```
CYCLE ACTION EDITOR (SWS):
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  PURPOSE: Step through multiple actions with one key            │
│                                                                  │
│  PRIMER — "Cycle Automation Mode":                              │
│  Press 1: Set to Write                                          │
│  Press 2: Set to Touch                                          │
│  Press 3: Set to Latch                                          │
│  Press 4: Set to Read                                           │
│  Press 5: Back to Write... (cycles)                             │
│                                                                  │
│  FEATURES:                                                       │
│  • IF/THEN logic                                                 │
│  • Conditional execution                                         │
│  • Toggle state indicators                                       │
│  • Nested cycle actions                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. PLUGIN HOSTING

### 8.1 Supported Formats

| Format | Windows | macOS | Linux | Notes |
|--------|---------|-------|-------|-------|
| **VST2** | ✅ | ✅ | ✅ | Legacy but widely used |
| **VST3** | ✅ | ✅ | ✅ | Modern standard |
| **AU** | ❌ | ✅ | ❌ | macOS only |
| **LV2** | ✅ | ✅ | ✅ | Open source, full support |
| **CLAP** | ✅ | ✅ | ✅ | **Native support! (v6.71+)** |
| **DX** | ✅ | ❌ | ❌ | Windows legacy |
| **JSFX** | ✅ | ✅ | ✅ | Native REAPER |

### 8.2 Plugin Bridging

```
PLUGIN BRIDGING:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  32-bit plugin u 64-bit REAPER:                                 │
│  ┌─────────────────┐    bridge    ┌─────────────────┐          │
│  │  REAPER x64     │◄───────────►│  Plugin x32     │          │
│  │                 │   (built-in) │                 │          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                  │
│  FIREWALLING:                                                    │
│  ┌─────────────────┐   separate   ┌─────────────────┐          │
│  │  REAPER         │◄───process──►│  Unstable       │          │
│  │  (protected)    │              │  Plugin         │          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                  │
│  Ako plugin crashuje → REAPER ostaje stabilan                   │
│                                                                  │
│  OPTIONS:                                                        │
│  • Run in same process (fastest)                                 │
│  • Run in dedicated process (safest)                             │
│  • Auto-detect 32/64                                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.3 FX Chains

```
FX CHAINS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SAVE FX CHAIN:                                                  │
│  1. Set up FX sa desired settings                               │
│  2. Select all FX in chain                                       │
│  3. Right-click → Save FX chain                                  │
│  4. .RfxChain file saved                                         │
│                                                                  │
│  LOAD FX CHAIN:                                                  │
│  1. Add FX → FX Chains folder                                    │
│  2. Entire chain loaded with settings                            │
│                                                                  │
│  DEFAULT FX CHAIN:                                               │
│  Right-click → "Save all FX as default chain for new tracks"    │
│  → Svi novi tracks automatski imaju ovu chain!                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.4 Track Templates

```
TRACK TEMPLATES:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SAVE TRACK TEMPLATE:                                            │
│  Right-click track → "Save tracks as track template"            │
│                                                                  │
│  INCLUDES:                                                       │
│  ├── All FX with settings                                        │
│  ├── Routing configuration                                       │
│  ├── Sends/Receives                                              │
│  ├── I/O settings                                                │
│  ├── Envelopes                                                   │
│  ├── Track color                                                 │
│  ├── Track icon                                                  │
│  └── Track name                                                  │
│                                                                  │
│  MULTI-TRACK TEMPLATES:                                          │
│  Select multiple tracks → Save as template                       │
│  → Saves entire routing structure (folders, sends, etc.)        │
│                                                                  │
│  FILE: .RTrackTemplate                                           │
│  LOCATION: REAPER/TrackTemplates/                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.5 PDC (Plugin Delay Compensation)

```
PDC FEATURES:
├── Automatic PDC
│   └── REAPER automatski kompenzuje sve plugin latencije
├── PDC reporting
│   └── View total track latency
├── Manual PDC offset
│   └── Per-plugin manual adjustment
├── PDC for sends
│   └── Sends are delay-compensated
└── Live monitoring bypass
    └── Option to bypass PDC for recording
```

### 8.6 Per-FX Oversampling (REAPER 7)

```
PER-FX OVERSAMPLING:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  REAPER 7 NEW FEATURE!                                          │
│                                                                  │
│  Bilo koji plugin može biti oversampled:                        │
│  • 2x (88.2/96 kHz)                                             │
│  • 4x (176.4/192 kHz)                                           │
│  • 8x (352.8/384 kHz)                                           │
│  • 16x (up to 768 kHz!)                                         │
│                                                                  │
│  RIGHT-CLICK plugin → Oversampling                              │
│                                                                  │
│  USE CASES:                                                      │
│  • Non-linear processors (distortion, saturation)               │
│  • Aliasing-prone plugins                                        │
│  • Mastering plugins                                             │
│  • Any plugin that benefits from higher sample rate             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.7 Sidechain Support

```
SIDECHAIN ANY PLUGIN:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  REAPER može sidechain-ovati BILO KOJI plugin,                  │
│  čak i ako plugin nema native sidechain support!                │
│                                                                  │
│  HOW:                                                            │
│  1. Set track to > 2 channels (e.g., 4)                         │
│  2. Route sidechain source to channels 3-4                      │
│  3. Configure plugin pin mapping                                 │
│  4. Map channels 3-4 to sidechain input                         │
│                                                                  │
│  ROUTING MATRIX:                                                 │
│  ┌────────────────────────────────────────┐                     │
│  │  Input     │  Plugin Input             │                     │
│  │  Ch 1-2    →  Audio L/R                │                     │
│  │  Ch 3-4    →  Sidechain L/R            │                     │
│  └────────────────────────────────────────┘                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. PROJECT MANAGEMENT

### 9.1 RPP Format (Human-Readable!)

```
RPP FORMAT:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  .RPP = Plain text file!                                         │
│                                                                  │
│  PRIMER:                                                         │
│  <REAPER_PROJECT 0.1 "7.0" 1234567890                           │
│    SAMPLERATE 48000 0 0                                          │
│    TEMPO 120 4 4                                                 │
│    <TRACK                                                        │
│      NAME "Vocal"                                                │
│      VOLPAN 1 0 -1 -1 1                                         │
│      <FXCHAIN                                                    │
│        <VST "VST: ReaEQ" "reaeq.dll"                            │
│          ...                                                     │
│        >                                                         │
│      >                                                           │
│    >                                                             │
│  >                                                               │
│                                                                  │
│  PREDNOSTI:                                                      │
│  • Može se editovati u text editoru                             │
│  • Version control friendly (Git)                                │
│  • Scripting/parsing sa Python, etc.                            │
│  • Nije binary blob                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

PROJECT FILES:
├── .RPP — Main project file
├── .RPP-BAK — Automatic backup
├── .RPP-UNDO — Undo history (optional)
└── .RPP-PROX — Subproject proxy render
```

### 9.2 Media Handling

```
MEDIA HANDLING OPTIONS:
├── Copy media to project folder
├── Reference media in original location
├── Move media to project folder
├── Peak files (.reapeaks)
│   └── Cached waveform displays
├── Media offline handling
│   └── Locate missing media
└── Media pooling
    └── Multiple items share source
```

### 9.3 Rendering

```
RENDER DIALOG:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SOURCE:                                                         │
│  ├── Master mix                                                  │
│  ├── Master mix + stems                                          │
│  ├── Stems (selected tracks)                                    │
│  ├── Region matrix                                               │
│  └── Selected media items                                        │
│                                                                  │
│  BOUNDS:                                                         │
│  ├── Custom time range                                           │
│  ├── Entire project                                              │
│  ├── Time selection                                              │
│  ├── Project regions                                             │
│  └── Selected regions                                            │
│                                                                  │
│  FORMAT:                                                         │
│  ├── WAV (PCM, float)                                           │
│  ├── AIFF                                                        │
│  ├── FLAC                                                        │
│  ├── MP3 (LAME)                                                  │
│  ├── OGG Vorbis                                                  │
│  ├── OGG Opus                                                    │
│  ├── Video (ffmpeg)                                              │
│  └── DDP (CD image)                                              │
│                                                                  │
│  OPTIONS:                                                        │
│  ├── Sample rate conversion                                      │
│  ├── Dither (on bit depth reduction)                            │
│  ├── Normalize                                                   │
│  ├── Add metadata                                                │
│  └── Add to project when done                                   │
│                                                                  │
│  DRY RUN:                                                        │
│  Render without output → shows loudness stats!                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 9.4 Batch Rendering

```
BATCH RENDERING:
├── Region-based batch
│   └── Each region → separate file
├── Matrix render
│   └── Custom region/track combinations
├── Wildcard naming
│   └── $project, $region, $track, etc.
├── Add to render queue
│   └── Render multiple projects in sequence
└── Render via command line
    └── Automation-friendly
```

### 9.5 Subprojects

```
SUBPROJECTS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  WORKFLOW:                                                       │
│  1. Drag .RPP file onto timeline                                 │
│  2. REAPER creates proxy audio (.RPP-PROX)                      │
│  3. Item plays rendered audio                                    │
│  4. Double-click → opens subproject in new tab                  │
│  5. Save subproject → auto re-renders proxy                     │
│                                                                  │
│  MARKERS:                                                        │
│  =START and =END markers define render bounds                   │
│                                                                  │
│  USE CASES:                                                      │
│  • Nested compositions                                           │
│  • Collaborative workflow                                        │
│  • Project organization                                          │
│  • CPU optimization (render heavy tracks)                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 9.6 Project Cleanup

```
PROJECT CLEANUP OPTIONS:
├── Remove unused media from project
├── Move/copy used media to project folder
├── Delete unused peak files
├── Consolidate takes
└── Remove empty items/tracks
```

---

## 10. METERING & VISUALIZATION

### 10.1 Track Meters

```
TRACK METER OPTIONS:
├── Peak
├── RMS
├── LUFS-M (Momentary, 400ms)
├── LUFS-S (Short-term, 3s)
├── VU
├── Pre-FX / Post-FX / Post-Fader
├── Stereo / Multi-channel
└── Custom colors
```

### 10.2 Master Meters

```
MASTER METER:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  DISPLAY OPTIONS:                                                │
│  ├── Peak with hold                                              │
│  ├── RMS                                                         │
│  ├── LUFS-M (Momentary)                                         │
│  ├── LUFS-S (Short-term)                                        │
│  └── Combined (Peak + RMS)                                      │
│                                                                  │
│  RIGHT-CLICK MENU:                                               │
│  ├── Meter mode selection                                        │
│  ├── Hold time                                                   │
│  ├── Decay speed                                                 │
│  ├── Color scheme                                                │
│  └── Reset peaks                                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 LUFS Metering

```
LUFS METERING (Built-in):
├── LUFS-M (Momentary)
│   └── 400ms window
├── LUFS-S (Short-term)
│   └── 3000ms window
├── LUFS-I (Integrated)
│   └── Via Dry Run render
├── True Peak
│   └── Via ReaLimit or JS plugins
└── Loudness Range (LRA)
    └── Via plugins

STREAMING TARGETS:
├── Spotify: -14 LUFS
├── Apple Music: -16 LUFS
├── YouTube: -14 LUFS
├── Amazon Music: -9 to -13 LUFS
└── Broadcast: -23 or -24 LUFS (EBU R128 / ATSC A/85)
```

### 10.4 Spectrum Analyzer

```
SPECTRUM ANALYSIS:
├── ReaEQ built-in analyzer
│   └── Real-time FFT display
├── ReaFIR spectrum view
│   └── FFT-based with editing
├── JSFX analyzers
│   ├── JS: Spectrum Analyzer
│   ├── JS: Spectrograph
│   └── JS: Goniometer
└── Third-party:
    ├── Voxengo SPAN (free)
    ├── iZotope Insight
    └── Melda MAnalyzer
```

### 10.5 Routing Diagram

```
ROUTING DIAGRAM:
View → Routing Matrix

┌─────────────────────────────────────────────────────────────────┐
│                TO:   Master  Bus1  Bus2  HW1-2  HW3-4          │
│  FROM:                                                          │
│  ─────────────────────────────────────────────────────────────  │
│  Track 1         ●     ○     ○     ○      ○                    │
│  Track 2         ●     ●     ○     ○      ○                    │
│  Track 3         ○     ●     ○     ○      ○                    │
│  Bus1            ●     ○     ○     ○      ○                    │
│  Bus2            ●     ○     ○     ●      ○                    │
│  Master          ○     ○     ○     ●      ●                    │
│                                                                  │
│  ● = Send enabled                                                │
│  ○ = No send                                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.6 Performance Meter

```
PERFORMANCE METER (View → Performance Meter):
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  CPU: [████████████░░░░░░░░] 58%                                │
│  RT:  [██████░░░░░░░░░░░░░░] 28%                                │
│  Disk: [████░░░░░░░░░░░░░░░░] 15%                               │
│  Memory: 1.2 GB / 16 GB                                          │
│                                                                  │
│  PER-FX BREAKDOWN:                                               │
│  Track 1: ReaEQ           0.1%                                   │
│  Track 1: ReaComp         0.2%                                   │
│  Track 2: Kontakt         12.4%  ←                              │
│  Track 3: Guitar Rig      8.1%                                   │
│  ...                                                             │
│                                                                  │
│  UNDERRUNS: 0                                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. UI/UX DESIGN

### 11.1 WALTER Theming Engine

```
WALTER = Window Arrangement Logic Template Engine for REAPER

CAPABILITIES:
├── Complete visual customization
│   ├── Track Control Panel (TCP)
│   ├── Mixer Control Panel (MCP)
│   ├── Envelope Panel
│   ├── Transport
│   └── Any REAPER window
├── Custom layouts
│   └── Rearrange any UI element
├── Vector graphics
│   └── Resolution-independent
├── Conditional elements
│   └── Show/hide based on state
└── Full color control
    └── Every pixel customizable

FILE STRUCTURE:
├── .ReaperTheme — Color settings
├── .ReaperThemeZip — Complete theme package
│   ├── rtconfig.txt — WALTER code
│   └── Images/ — PNG graphics
└── Location: REAPER/ColorThemes/
```

### 11.2 Theme Adjuster (REAPER 7)

```
THEME ADJUSTER:
Options → Themes → Theme adjuster

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  TRACK CONTROLS:                                                 │
│  ├── Drag elements to reorder                                   │
│  ├── Enable/disable elements                                    │
│  ├── Adjust spacing                                             │
│  └── Set opacity                                                │
│                                                                  │
│  MIXER CONTROLS:                                                 │
│  ├── Channel strip layout                                       │
│  ├── Fader size                                                 │
│  └── Meter position                                             │
│                                                                  │
│  COLORS:                                                         │
│  ├── Track colors                                                │
│  ├── UI element colors                                          │
│  └── Waveform colors                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3 Screensets

```
SCREENSETS:
View → Screensets

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SCREENSET = Saved window layout                                │
│                                                                  │
│  SAVE:                                                           │
│  • Window positions                                              │
│  • Window sizes                                                  │
│  • Visible windows                                               │
│  • Track heights                                                 │
│  • Zoom level                                                    │
│  • Scroll position                                               │
│                                                                  │
│  SLOTS: 10 screensets (customizable shortcuts)                  │
│                                                                  │
│  USE CASES:                                                      │
│  • Mixing layout (big mixer)                                    │
│  • Editing layout (big timeline)                                │
│  • Recording layout (big meters)                                │
│  • Dual monitor setups                                          │
│                                                                  │
│  SHORTCUT: F-keys (F1-F10) + modifiers                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 11.4 Toolbars

```
TOOLBARS:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  CUSTOMIZATION:                                                  │
│  • Add/remove buttons                                            │
│  • Assign any action to button                                  │
│  • Custom icons                                                  │
│  • Multiple toolbars                                             │
│  • Floating/docked                                               │
│                                                                  │
│  RIGHT-CLICK TOOLBAR → Customize toolbar                        │
│                                                                  │
│  TOOLBAR TYPES:                                                  │
│  ├── Main toolbar                                                │
│  ├── MIDI editor toolbar                                         │
│  ├── Custom floating toolbars                                   │
│  └── Context-specific toolbars                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 11.5 Docking

```
DOCKING SYSTEM:
├── Drag any window to dock
├── Multiple dock positions
│   ├── Left
│   ├── Right
│   ├── Top
│   ├── Bottom
│   └── Tabbed (multiple windows in one dock)
├── Resizable dock panels
├── Save/restore with screensets
└── Per-window docking memory
```

### 11.6 Keyboard Shortcuts

**REAPER je 100% customizable:**

```
KEYBOARD CUSTOMIZATION:
Options → Customize menus/toolbars
Actions → Show action list → Add shortcut

FEATURES:
├── Any action can have multiple shortcuts
├── Any key combination possible
├── Context-aware (different per section)
├── Import/export key maps
├── Mouse modifier customization
├── MIDI key learning
└── OSC control mapping

DEFAULT NOTABLE SHORTCUTS:
├── Space — Play/Stop
├── R — Record
├── S — Split
├── M — Insert marker
├── Tab — Next transient
├── G — Group items
├── H — Heal split
├── D — Dynamic split
└── ? — Actions list
```

---

## 12. JEDINSTVENE KARAKTERISTIKE

### 12.1 Portable Installation

```
PORTABLE INSTALLATION:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  REAPER može raditi sa USB flash drive!                         │
│                                                                  │
│  PORTABLE INSTALL:                                               │
│  ├── Kompletna aplikacija u jednom folderu                      │
│  ├── Nema registry/system files                                  │
│  ├── Settings, plugins, themes — sve prenosivo                  │
│  ├── Različite verzije mogu koegzistirati                       │
│  └── Backup = copy folder                                        │
│                                                                  │
│  USE CASES:                                                      │
│  • Studio-to-studio mobility                                    │
│  • Multiple configurations                                       │
│  • Testing new versions safely                                  │
│  • Disaster recovery (always have backup)                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.2 Extreme Efficiency

```
REAPER SIZE COMPARISON:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  DAW                    Install Size                             │
│  ─────────────────────────────────────                          │
│  REAPER                 ~20 MB  ←←←                             │
│  Ableton Live           ~2 GB                                   │
│  Pro Tools              ~4 GB                                   │
│  Cubase                 ~15 GB                                  │
│  Logic Pro              ~70 GB                                  │
│                                                                  │
│  REAPER je ~100-3500x manji od konkurencije!                    │
│                                                                  │
│  MEMORY USAGE:                                                   │
│  Idle: ~50 MB                                                    │
│  Heavy project: ~200-500 MB                                     │
│                                                                  │
│  STARTUP TIME:                                                   │
│  Cold start: < 2 seconds                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.3 Linux Native Support

```
LINUX SUPPORT:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  REAPER je jedan od RETKIH profesionalnih DAW-ova               │
│  sa NATIVE Linux podrškom!                                       │
│                                                                  │
│  SUPPORTED:                                                      │
│  ├── Debian/Ubuntu                                               │
│  ├── Fedora                                                      │
│  ├── Arch Linux                                                  │
│  ├── CentOS/RHEL                                                │
│  └── Bilo koja distro sa GTK+3                                  │
│                                                                  │
│  AUDIO SYSTEMS:                                                  │
│  ├── JACK                                                        │
│  ├── PipeWire                                                    │
│  ├── ALSA                                                        │
│  └── PulseAudio (not recommended)                               │
│                                                                  │
│  PLUGIN FORMATS:                                                 │
│  ├── LV2 (native Linux)                                         │
│  ├── VST2/VST3 (Linux versions)                                 │
│  ├── CLAP (Linux versions)                                      │
│  └── JSFX (cross-platform)                                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.4 NINJAM Integration

```
NINJAM (Network Jam):
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  NINJAM = Real-time online jam sessions                         │
│                                                                  │
│  HOW IT WORKS:                                                   │
│  • Svi sviraju u sync, ali sa latency offset                    │
│  • Server čuva intervale (e.g., 8 bars)                         │
│  • Svaki interval → hear previous interval from others          │
│  • Creates creative "delay effect"                               │
│                                                                  │
│  FEATURES:                                                       │
│  ├── ReaNINJAM plugin (built into REAPER)                       │
│  ├── Connect to public/private servers                          │
│  ├── Personal mix control                                        │
│  ├── Session recording                                           │
│  ├── Import sessions for remixing                               │
│  └── Cross-platform (Win/Mac/Linux)                             │
│                                                                  │
│  SETUP: FX → ReaNINJAM → Connect to server                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.5 ReaMote (Distributed Processing)

```
REAMOTE:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ReaMote = Network distributed FX processing                    │
│                                                                  │
│  ┌──────────────┐         ┌──────────────┐                      │
│  │   MAIN       │  LAN    │   SLAVE      │                      │
│  │   REAPER     │◄───────►│   REAPER     │                      │
│  │   (Control)  │         │   (FX only)  │                      │
│  └──────────────┘         └──────────────┘                      │
│                                                                  │
│  FEATURES:                                                       │
│  ├── Offload heavy plugins to another computer                  │
│  ├── Network-transparent plugin hosting                         │
│  ├── Automatic latency compensation                             │
│  └── Same plugin on multiple machines                           │
│                                                                  │
│  USE CASES:                                                      │
│  • Large orchestral templates                                    │
│  • Heavy sample libraries (Kontakt)                             │
│  • More CPU for mixing                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.6 Video Editing Capabilities

```
VIDEO IN REAPER:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  SUPPORTED FORMATS (via FFmpeg):                                │
│  ├── AVI                                                         │
│  ├── MOV                                                         │
│  ├── MP4                                                         │
│  ├── WMV                                                         │
│  ├── MPG                                                         │
│  └── More with FFmpeg codecs                                    │
│                                                                  │
│  FEATURES:                                                       │
│  ├── Video on timeline (like audio items)                       │
│  ├── Video preview window (Ctrl+Shift+V)                        │
│  ├── Frame-accurate editing                                      │
│  ├── Video rendering with new audio                             │
│  ├── Video processor (effects via EEL2)                         │
│  ├── Nested video                                                │
│  └── Video fade/crossfade                                        │
│                                                                  │
│  USE CASES:                                                      │
│  ├── Audio post-production                                       │
│  ├── Podcast video                                               │
│  ├── Music videos (sync)                                         │
│  └── Simple video edits                                          │
│                                                                  │
│  LIMITATION: Not a full video NLE                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.7 Pricing & Licensing

```
REAPER LICENSING:
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  DISCOUNTED LICENSE: $60                                         │
│  • For individual/small business < $20k/year revenue            │
│  • Educational use                                               │
│                                                                  │
│  COMMERCIAL LICENSE: $225                                        │
│  • For business > $20k/year revenue                             │
│  • Multi-user sites                                              │
│                                                                  │
│  INCLUDES:                                                       │
│  ├── All features (no "lite" version)                           │
│  ├── All platforms (one license = all OS)                       │
│  ├── Free updates (2 major versions)                            │
│  ├── Priority forum support                                      │
│  └── No dongles/iLok required                                   │
│                                                                  │
│  EVALUATION:                                                     │
│  • 60-day full-featured trial                                   │
│  • No features disabled                                          │
│  • Trial reminder on launch (that's it)                         │
│                                                                  │
│  COMPARISON:                                                     │
│  Pro Tools: $599/year subscription                              │
│  Cubase Pro: $579 + yearly updates                              │
│  Ableton Live Suite: $749                                       │
│  Logic Pro: $199 (Mac only)                                     │
│  REAPER: $60 lifetime* (or $225 commercial)                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## IMPLEMENTACIONE NAPOMENE ZA FLUXFORGE STUDIO

### Šta preuzeti od REAPER-a:

1. **Anticipative FX Processing koncept** — pre-render FX chains
2. **Track = Everything filozofija** — eliminisati tipove track-ova
3. **Per-FX oversampling** — critical za saturaciju
4. **JSFX-like scripting** — rf-script već implementira Lua
5. **RPP-like project format** — human-readable JSON
6. **FX Containers** — implementirati u rf-engine
7. **Razor editing** — implementirati u Flutter UI
8. **Swipe comping** — implementirati lanes sistem
9. **Dynamic split** — implementirati transient detection
10. **Folder tracks as buses** — pojednostaviti routing

### Šta izbegavati:

1. Kompleksnost WALTER theming sistema (previše fleksibilno)
2. Action list sa 3000+ akcija (teško za nove korisnike)
3. Steep learning curve customization-a

### Key Takeaways:

| REAPER Feature | FluxForge Implementation |
|----------------|-------------------------|
| Anticipative FX | Guard Path (rf-realtime) |
| 768kHz oversampling | Per-FX oversampling u rf-dsp |
| JSFX | rf-script Lua API |
| ReaPlugs | rf-dsp processors |
| RPP format | JSON project format (rf-file) |
| Unlimited tracks | Already implemented |
| FX Containers | rf-engine FX chains |
| Linux native | Cross-platform Flutter |

---

## IZVORI

- [REAPER Official](https://www.reaper.fm/)
- [REAPER ReaPlugs](https://www.reaper.fm/reaplugs/)
- [REAPER JSFX Programming](https://www.reaper.fm/sdk/js/js.php)
- [REAPER ReaScript](https://www.reaper.fm/sdk/reascript/reascript.php)
- [REAPER WALTER Theme Development](https://www.reaper.fm/sdk/walter/)
- [SWS Extensions](https://www.sws-extension.org/)
- [REAPER Blog](https://reaper.blog/)
- [Sound on Sound REAPER Articles](https://www.soundonsound.com/techniques/reaper)
- [Cockos Wiki](https://wiki.cockos.com/)

---

**Dokument kreiran za FluxForge Studio development team.**
**Verzija REAPER-a analizirana: 7.x (2024-2025)**
