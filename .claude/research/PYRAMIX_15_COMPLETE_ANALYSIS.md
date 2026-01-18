# PYRAMIX 15 — Ultimativna Tehnička Analiza

**Merging Technologies SA, Švajcarska**
**Verzija:** 15.x (2024)
**Cena:** ~$3,000 - $8,000+ (zavisno od paketa)

---

## EXECUTIVE SUMMARY

Pyramix je najnapredniji DAW na svetu za **klasičnu muziku**, **broadcast**, **post-produkciju** i **high-resolution mastering**. Jedini je DAW sa:

1. **MassCore Engine** — CPU core isolation za near-zero latency
2. **Native DSD editing** — Jedini pravi DSD DAW
3. **RAVENNA native** — Pioneer IP audio networkinga
4. **384 kanala I/O** — Najveci broj kanala u industriji
5. **23,000+ ms PDC** — Neogranicena plugin chain
6. **NHK 22.2 native** — Do 64 kanala surround

**Cena opravdanja:** $8,000+ za Premium zato što nema alternative — Pyramix je JEDINI koji može sve ovo.

---

## 1. MASSCORE ENGINE ARCHITECTURE

### 1.1 Fundamentalni Koncept

MassCore je **revolucionarna tehnologija** koju nijedan drugi DAW nema. Koncept:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRADITIONAL DAW                               │
│                                                                  │
│  Audio Software ──► OS Kernel ──► CPU                           │
│                      ▲                                           │
│                      │                                           │
│              LATENCY (OS scheduling,                             │
│              context switching,                                  │
│              buffer management)                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    MASSCORE DAW                                  │
│                                                                  │
│  Audio Software ──► DIRECT PIPE ──► Isolated CPU Core(s)        │
│                                                                  │
│              NO OS INVOLVEMENT                                   │
│              = NEAR-ZERO LATENCY                                │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Kako MassCore Funkcioniše

1. **Core Isolation:**
   - MassCore "krije" 1-4+ CPU jezgara od Windows OS-a
   - Ova jezgra postaju **dedikirana audio DSP jezgra**
   - OS nikada ne može da zakaže druge taskove na njima

2. **Direct Pipe Komunikacija:**
   - Pyramix komunicira **direktno** sa izolovanim jezgrima
   - Nema OS scheduling overhead-a
   - Nema context switching-a
   - Nema buffer-a koji OS kontroliše

3. **RTX64 Real-Time Kernel:**
   - MassCore koristi **IntervalZero RTX64** kernel extension
   - RTX64 v4.5.1.7199+ required
   - Pretvara Windows PC u **hard real-time sistem**
   - Deterministicko ponašanje — garantovano vreme izvršavanja

### 1.3 I/O Kapaciteti po Sample Rate-u

| Sample Rate | MassCore I/O | Native I/O | Format |
|-------------|--------------|------------|--------|
| 44.1/48 kHz (1FS) | **384 channels** | 128 ch | PCM |
| 88.2/96 kHz (2FS) | 192 channels | 64 ch | PCM |
| 176.4/192 kHz (4FS) | **96 channels** | 32 ch | PCM |
| 352.8/384 kHz (8FS) | **48 channels** | 16 ch | DXD |
| DSD64 (2.8 MHz) | 64 channels | 24 ch | 1-bit |
| DSD128 (5.6 MHz) | 48 channels | 16 ch | 1-bit |
| DSD256 (11.2 MHz) | **48 channels** | 8 ch | 1-bit |

**Ovo je NEVEROVATNO** — 384 kanala simultano @ 48kHz je više nego bilo koji drugi DAW.

### 1.4 RAVENNA/AES67 Native Support

MassCore ima **native RAVENNA konekciju** — bez ASIO driver-a:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRADITIONAL AUDIO                             │
│                                                                  │
│  DAW ──► ASIO Driver ──► Audio Interface ──► Analog             │
│                                                                  │
│              Multiple conversion points                          │
│              Driver latency                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    MASSCORE + RAVENNA                            │
│                                                                  │
│  DAW ──► MassCore ──► Gigabit Ethernet ──► RAVENNA Device       │
│                                                                  │
│              Direct network audio                                │
│              Near-zero latency                                   │
│              768 channels total possible                         │
└─────────────────────────────────────────────────────────────────┘
```

**Podržani Protokoli:**
- **RAVENNA** — Merging-ov IP audio standard
- **AES67** — Industry standard (potpuna kompatibilnost)
- **SMPTE ST2110-30** — Broadcast IP video/audio standard
- **Dante** — Via AES67 compatibility mode

### 1.5 ST2110 Broadcast Integration

Za broadcast facility-je, MassCore podržava SMPTE ST2110:

- **ST2110-10**: System timing (PTP)
- **ST2110-20**: Uncompressed video
- **ST2110-30**: Audio (AES67 baziran)
- **ST2110-40**: Ancillary data

### 1.6 PTP Sinhronizacija (IEEE 1588)

MassCore koristi **PTPv2 (IEEE1588-2008)** za network sync:

```
Best Master Clock Algorithm (BMCA):
├── Automatski izbor Grandmaster clocka
├── Sub-microsecond accuracy
├── Network-wide synchronization
└── Failover protection
```

### 1.7 PDC (Plugin Delay Compensation)

**23,000+ ms PDC** — Praktično neograniceno:

| DAW | Max PDC |
|-----|---------|
| **Pyramix** | **23,000+ ms** |
| Pro Tools | ~16,000 ms |
| Logic Pro | ~10,000 ms |
| Cubase | ~8,000 ms |
| FL Studio | ~4,000 ms |

Ovo znači da možete koristiti **bilo koji linear-phase plugin** bez brige o sync problemima.

### 1.8 Near-Zero Latency Objašnjenje

```
Round-trip latency comparison @ 48kHz:

Traditional DAW + ASIO:
├── Input buffer: 128 samples (2.67ms)
├── Processing: Variable
├── Output buffer: 128 samples (2.67ms)
└── TOTAL: ~6-10ms minimum

MassCore + RAVENNA:
├── Network: ~0.5ms
├── MassCore processing: ~0.3ms
├── Output: ~0.5ms
└── TOTAL: ~1.3-2ms
```

**MassCore je brži od bilo koje DSP kartice** osim možda Avid HDX (koja košta $15,000+).

---

## 2. DSP PROCESSORS

### 2.1 VS3 Plugin Format

VS3 je **Merging-ov proprietary plugin format** optimizovan za:

- **32-channel support** (vs 2ch za većinu VST)
- **Native sidechain routing**
- **MassCore optimizacija**
- **DXD processing** (352.8kHz internal)

**VS3 vs VST Poređenje:**

| Feature | VS3 | VST3 | VST2 |
|---------|-----|------|------|
| Max Channels | **32** | 8 (typical) | 2 |
| Sidechain | Native | Varies | Manual |
| MassCore | Optimized | Hosted | Hosted |
| DXD Rate | Native | Via conversion | Via conversion |
| Latency Report | Accurate | Varies | Often wrong |

### 2.2 Pyramix Stock Plugins (VS3)

**Core Plugins (Uključeni):**

| Plugin | Tip | Opis |
|--------|-----|------|
| **EQ** | Parametric | Mastering-grade, multi-band |
| **Dynamics** | Compressor/Limiter | Transparent, surgical |
| **Strip Tools** | Channel Strip | EQ + Dynamics + Gate |
| **Bus Tools** | Bus Processor | Master bus chain |
| **PanNoir** | Phase Correction | Multi-mic phase alignment |

**EVO Channel Strip:**
```
Signal Flow:
├── Gain/Drive
├── Phase (polarity + fine)
├── Compressor
├── EQ (parametric)
├── DeEsser
├── Expander
├── Transient Designer
└── Sustain Designer
```

### 2.3 Third-Party VS3 Plugins

**FLUX VS3 Bundle:**
- Alchemist (multiband dynamics)
- BitterSweet (transient shaper)
- Epure (linear-phase EQ)
- IRCAM Tools (analysis)
- Pure Compressor
- Pure Expander
- Syrah (dynamics)
- Verb Session / Verb Full (reverb)

**CEDAR VS3 Bundle:**
- Auto Declick
- Decrackle
- Dehiss
- Dethump
- **Retouch 8** (spectral editing)

**Algorithmix VS3:**
- **ReNOVAtor** (real-time spectral repair)
- LinearPhase PEQ (mastering EQ)

### 2.4 VST2/VST3 Hosting

Pyramix hostuje sve VST2 i VST3 plugine:

- Full sidechain support (Pyramix 15+)
- Channel selection za multikanal
- MassCore i Native mode
- Clip-based FX (non-destructive)

### 2.5 Real-Time vs Offline Processing

```
REAL-TIME PROCESSING:
├── VS3 plugins — Native, lowest latency
├── VST3 plugins — Hosted, good latency
├── VST2 plugins — Hosted, variable latency
└── DXD conversion — Automatic for DSD

OFFLINE PROCESSING:
├── CEDAR Retouch — Spectral editing
├── DSD Render — Bit-perfect DSD copying
├── Batch SRC — Sample rate conversion
└── Analysis tools — FFT, loudness
```

### 2.6 DSD Processing Specifics

**DSD ne može da se procesira direktno** — 1-bit stream ne dozvoljava matematiku.

Pyramix rešenje:

```
DSD Processing Pipeline:

┌─────────────────────────────────────────────────────────────────┐
│ Original DSD64/128/256 ──► DXD (352.8/705.6/1411.2 kHz PCM)    │
│                                                                  │
│ DXD Processing:                                                  │
│ ├── EQ, dynamics, effects                                       │
│ ├── Mixing, automation                                          │
│ └── Level adjustments                                           │
│                                                                  │
│ DXD ──► SDM Modulator ──► Output DSD64/128/256                 │
└─────────────────────────────────────────────────────────────────┘
```

**SDM Modulator Types:**
- SDM A — Fastest, good quality
- SDM B — Balanced speed/quality
- SDM C — High quality
- **SDM D** — Highest quality (OFFLINE ONLY, very slow)

**DSD Render Tool:**
Za **bit-perfect DSD copying** bez konverzije:
- Kopira DSD digit-for-digit
- Bez DXD konverzije
- Samo za editing (cuts, fades)

---

## 3. MIXER ARCHITECTURE

### 3.1 Virtual Studio Koncept

Pyramix mixer se zove **Virtual Studio** — simulira hardware console:

```
┌─────────────────────────────────────────────────────────────────┐
│                    VIRTUAL STUDIO ARCHITECTURE                   │
│                                                                  │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐         │
│  │ INPUT   │   │ INPUT   │   │ INPUT   │   │ INPUT   │         │
│  │ STRIP 1 │   │ STRIP 2 │   │ STRIP N │   │ STRIP X │         │
│  └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘         │
│       │             │             │             │               │
│       ▼             ▼             ▼             ▼               │
│  ┌─────────────────────────────────────────────────────┐       │
│  │                    BUS MATRIX                        │       │
│  │  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ │       │
│  │  │ STEM  │ │ STEM  │ │  AUX  │ │  AUX  │ │MASTER │ │       │
│  │  │ BUS 1 │ │ BUS 2 │ │ SEND 1│ │ SEND 2│ │  BUS  │ │       │
│  │  └───────┘ └───────┘ └───────┘ └───────┘ └───────┘ │       │
│  └─────────────────────────────────────────────────────┘       │
│                              │                                  │
│                              ▼                                  │
│                    ┌─────────────────┐                         │
│                    │   MONITORING    │                         │
│                    │     SECTION     │                         │
│                    └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Bus Routing Capabilities

**Podržani Bus Formati:**

| Format | Channels | Use Case |
|--------|----------|----------|
| Mono | 1 | Voiceover |
| Stereo | 2 | Standard |
| LCR | 3 | Film dialog |
| Quad | 4 | Legacy surround |
| 5.0 | 5 | Film surround |
| 5.1 | 6 | DVD/Blu-ray |
| 6.1 | 7 | SDDS |
| 7.1 | 8 | Cinema |
| 7.1.2 | 10 | Atmos base |
| 7.1.4 | 12 | Atmos music |
| 9.1.4 | 14 | Extended Atmos |
| 9.1.6 | 16 | Full Atmos |
| 13.1 | 14 | Auro-3D |
| **22.2** | 24 | NHK Super Hi-Vision |
| Ambisonic 1st | 4 | FOA |
| Ambisonic 3rd | 16 | TOA |
| **Ambisonic 7th** | **64** | HOA |

### 3.3 Surround Mixing do 22.2

Pyramix je **prvi DAW** koji je podržao NHK 22.2:

```
NHK 22.2 Speaker Layout:
┌─────────────────────────────────────────────────────────────────┐
│ TOP LAYER (9 speakers):                                          │
│ TpFL  TpFC  TpFR                                                │
│    TpSiL    TpSiR                                               │
│ TpBL  TpBC  TpBR                                                │
│                                                                  │
│ MIDDLE LAYER (10 speakers):                                      │
│ FL   FLc   FC   FRc   FR                                        │
│   SiL                 SiR                                       │
│ BL          BC          BR                                      │
│                                                                  │
│ BOTTOM LAYER (3 speakers):                                       │
│ BtFC  BtFL  BtFR                                                │
│                                                                  │
│ LFE (2 channels):                                                │
│ LFE1  LFE2                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 Dolby Atmos Implementation

**Pyramix ima najkompletniju Atmos integraciju:**

1. **Hybrid Buses:**
   - Bed channels (7.1.2 max) + Objects
   - Bilo koji kanal može biti Object
   - Automatsko mapiranje

2. **Renderer Communication:**
   - Real-time sync sa Dolby Atmos Renderer
   - Automatska konfiguracija
   - ADM import/export (96kHz!)

3. **Beyond 7.1.2 Beds:**
   ```
   Problem: Dolby Atmos beds su max 7.1.2

   Pyramix rešenje:
   ├── Detektuje veće bus formate (5.1.4, 7.1.4, 9.1.6)
   ├── Mapira dodatne kanale kao Static Objects
   ├── Šalje ispravne metapodatke Rendereru
   └── Emulira speaker layout
   ```

4. **ADM Export:**
   - Direct ADM export bez Renderer-a
   - 48kHz i 96kHz (Pyramix 14.1+)
   - Full metadata preservation

### 3.5 3D Audio Panning

Pyramix ima **built-in 3D panner**:

```
3D Panner Features:
├── X/Y/Z positioning
├── Distance attenuation
├── Spread control
├── LFE send
├── Divergence
├── Object vs Bed routing
└── Automation (sample-accurate)
```

### 3.6 Monitor Controller

**Software Monitor Controller:**

```
Monitor Section Features:
├── Multiple speaker sets
├── Speaker mute/solo
├── Phase invert per speaker
├── Dim
├── Mono sum
├── L/R swap
├── Reference level
├── Talkback routing
├── Listenback
├── Downmix preview (5.1→stereo, etc.)
└── Binaural preview
```

**Remote Control:**
- MIDI control (foot pedals)
- OSC protocol
- Hardware controller support

### 3.7 Talkback/Listenback

```
Talkback System:
┌─────────────────────────────────────────────────────────────────┐
│ Control Room Mic ──► Pyramix Input ──► Cue/Foldback Output     │
│                            │                                    │
│                            ▼                                    │
│                    Optional Recording                           │
│                    (for slate/comments)                         │
└─────────────────────────────────────────────────────────────────┘

Listenback System:
┌─────────────────────────────────────────────────────────────────┐
│ Studio Mic ──► Pyramix Input ──► Control Room Speakers         │
│                                                                  │
│ (Hear what musicians are saying)                                │
└─────────────────────────────────────────────────────────────────┘
```

**Backup Recorder Trik:**
- Main recorder: Bez talkback
- Backup recorder: Sa talkback
- Rezultat: Clean takes + Commented session backup

---

## 4. TIMELINE/ARRANGEMENT

### 4.1 Sequence Structure

Pyramix koristi **Sequence** umesto "Session" ili "Project":

```
Project Structure:
├── Project File (.pmx)
│   ├── Sequence 1
│   │   ├── Timeline
│   │   ├── Clips
│   │   ├── Automation
│   │   └── Markers
│   ├── Sequence 2
│   ├── Sequence N
│   └── Shared Media Pool
└── Media Folder
    ├── Audio Files
    ├── Rendered Files
    └── Backup Files
```

### 4.2 Multi-Sequence Editing

**Jedinstvena Pyramix mogućnost:**

- Multiple sequences u jednom projektu
- Source/Destination između sequences
- Independent zoom/position per sequence
- Simultani prikaz više sequences

### 4.3 Clip Handling

**Clip Features:**
```
Clip Properties:
├── Non-destructive editing
├── Clip gain
├── Clip-based FX (Pyramix 15)
├── Fade in/out per clip
├── Color coding
├── Take flagging (Good/Bad)
├── Metadata
└── Linked/Unlinked channels
```

**Mixed Format Timeline:**
- Bilo koji file format na istom timeline-u
- Mixed sample rates
- Mixed bit depths
- Mixed channel counts
- Bez renderovanja!

### 4.4 Fades

**Fade Types:**
- Linear
- S-Curve
- Logarithmic
- Exponential
- Equal Power
- Equal Gain
- Custom curve

**Fade Editor:**
```
┌─────────────────────────────────────────────────────────────────┐
│                    FADE EDITOR                                   │
│                                                                  │
│    ┌─────────────────────────────────┐                          │
│    │           ╱──────               │  ← Fade curve            │
│    │         ╱                       │                          │
│    │       ╱                         │                          │
│    │     ╱                           │                          │
│    │   ╱                             │                          │
│    │ ╱                               │                          │
│    └─────────────────────────────────┘                          │
│                                                                  │
│    Curve Type: [S-Curve ▼]                                      │
│    Duration: [250 ms]                                           │
│    Tension: [0.5]                                               │
└─────────────────────────────────────────────────────────────────┘
```

### 4.5 Crossfades

**Crossfade za DSD:**
- DSD crossfades su procesirana u DXD
- Samo crossfade region se konvertuje
- Ostatak ostaje native DSD

### 4.6 Automation

**Automation System:**
```
Automation Features:
├── Sample-accurate
├── Automation Versions (multiple per timeline)
├── A/B comparison
├── Punch in/out
├── Trim mode
├── Snapshot
├── Copy/paste between tracks
└── 23,000+ ms delay compensation
```

**Automation Versions:**
- Scroll kroz automation history
- Save multiple versions
- Compare during playback
- Instant recall

### 4.7 Markers

**Marker Types:**
- Standard markers
- CD Track markers (Red Book)
- CD Index markers
- Loop markers
- Punch markers
- Comment markers
- Timecode markers

### 4.8 CD Track Markers (Red Book)

```
CD Marker Properties:
├── Track number (1-99)
├── Index number (0-99)
├── ISRC code
├── Pre-emphasis flag
├── Copy prohibition
├── Start time (frame-accurate)
└── Pause time
```

---

## 5. EDITING CAPABILITIES

### 5.1 4-Point Editing (Source/Destination)

**Ovo je RAZLOG zašto klasičari koriste Pyramix:**

```
Source/Destination Workflow:
┌─────────────────────────────────────────────────────────────────┐
│ SOURCE WINDOW (Takes/Recordings):                                │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Take 1: [====IN========OUT====]                             │ │
│ │ Take 2: [========IN====OUT========]                         │ │
│ │ Take 3: [====IN===========OUT==]                            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ DESTINATION WINDOW (Final Edit):                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ [====][IN----DEST----OUT][=====]                            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ 3-Point Edit: Source IN + Source OUT + Dest IN                  │
│ 4-Point Edit: Source IN + Source OUT + Dest IN + Dest OUT       │
│               (speed change / fit-to-fill)                       │
└─────────────────────────────────────────────────────────────────┘
```

**Prednosti Source/Destination:**
- Simultani pregled više takes
- Instant compare
- Multi-track editing (32-100+ tracks odjednom)
- Broadcast-standard workflow

### 5.2 Ripple Editing

**Ripple Modes:**
- Insert-Ripple: Ubaci i pomeri sve desno
- Delete-Ripple: Obriši i povuci sve levo
- Ripple with crossfade
- Track-specific ripple
- All-tracks ripple

### 5.3 Slip Editing

**Slip bez promene pozicije:**
- Audio content slip unutar granica
- Maintain clip boundaries
- Visual preview
- Linked/unlinked channel slip

### 5.4 Scrubbing (DSD Scrub!)

**Pyramix je JEDINI DAW koji može scrubovati DSD:**

```
DSD Scrubbing Process:
├── Real-time DXD conversion
├── Variable speed playback
├── Audible pitch changes
└── Frame-accurate positioning
```

**Scrub Modes:**
- Jog (frame-by-frame)
- Shuttle (variable speed)
- Audio scrub (hear audio)
- Silent scrub (visual only)

### 5.5 Spectral Editing

**CEDAR Retouch 8 (Premium Feature):**

```
Spectral Editing Capabilities:
├── Time-Frequency display
├── Brush selection tools
├── Match & Find (ML-based)
├── Spectral repair
├── Clone tool
├── Patch tool
├── Attenuate/Boost
└── Remove
```

**Use Cases:**
- Remove coughs from classical recording
- Fix microphone bumps
- Remove electrical hum
- Repair clipped samples
- Remove wind noise

### 5.6 Batch Processing

**Batch Capabilities:**
- Sample rate conversion (HEPTA algorithm)
- Format conversion
- Loudness normalization
- File naming
- Metadata embedding
- DSD⟷PCM conversion

---

## 6. RECORDING CAPABILITIES

### 6.1 Multi-Track Recording

**Capacity:**
| Engine | Max Tracks @ 48kHz |
|--------|-------------------|
| Native | 128 |
| MassCore | **384** |

**Features:**
- Simultaneous record + playback
- Independent recorder (rec during edit)
- Pre-allocated disk space
- Auto-take numbering
- Take flagging (Good/Bad/Color)

### 6.2 DSD Recording

**Native DSD Recording:**
```
DSD Recording Specs:
├── DSD64 (2.8224 MHz): 64 channels max
├── DSD128 (5.6448 MHz): 48 channels max
├── DSD256 (11.2896 MHz): 48 channels max
├── Frame-based start/stop
└── DSDIFF file format
```

**Važno:** DSD snimanje mora početi/završiti na frame boundaries da bi se izbegli klikovi.

### 6.3 Backup Recording

**Dual Media Path:**
```
Recording Safety:
├── Primary Media Path ──► SSD 1
├── Backup Media Path ──► SSD 2 (different bus!)
├── Independent file sets
├── Automatic mirroring
└── Different codec options per path
```

**Keyboard Lockout:**
Za kritične snimke (Royal Wedding, live concerts):
- Disables all keyboard input
- Prevents accidental stops
- Only mouse or hardware control

### 6.4 Takes Management

```
Takes System:
├── Auto-increment take numbers
├── Color coding (user-configurable)
├── Good/Bad flagging
├── Delete bad takes (recoverable)
├── Quick compare
└── Metadata per take
```

### 6.5 Auto-Punch

**Punch Modes:**
- Manual punch (keyboard/footswitch)
- Auto-punch (marker-based)
- Loop punch (multiple takes)
- Pre-roll adjustable
- Post-roll adjustable

### 6.6 Pre/Post Roll

```
Pre/Post Roll Settings:
├── Pre-roll: 0-60 seconds
├── Post-roll: 0-60 seconds
├── Count-in beats (for music)
├── Audible/silent options
└── Auto-stop after post-roll
```

---

## 7. MASTERING & CD

### 7.1 Mastering Workflow

**Pyramix je Industry Standard za klasično masterovanje:**

```
Mastering Signal Flow:
┌─────────────────────────────────────────────────────────────────┐
│ Source Audio ──► Input Strip ──► Processing Chain ──► Master   │
│                                                                  │
│ Processing Chain:                                               │
│ ├── Gain staging                                                │
│ ├── EQ (VS3/Flux Epure)                                        │
│ ├── Dynamics (VS3/Flux Pure Compressor)                        │
│ ├── Limiting (True Peak)                                        │
│ ├── Dither (POW-r)                                             │
│ └── SRC (HEPTA)                                                │
│                                                                  │
│ Master Bus ──► Final Check ──► Export                          │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Red Book CD Authoring

**Complete Red Book Compliance:**

```
Red Book Specifications:
├── Audio: 44.1kHz, 16-bit, stereo
├── Tracks: 1-99
├── Indices per track: 0-99
├── Minimum track length: 4 seconds
├── Maximum album length: 79:57
├── Pre-gap: 2 seconds (first track)
├── Frame accuracy: 1/75 second
└── Subcode channels: P, Q
```

**Pyramix CD Features:**
- Visual CD track layout
- Gap editing (adjustable)
- Index point placement
- Track transition preview
- CD-Text editing
- ISRC per track
- UPC/EAN for album
- Pre-emphasis flag

### 7.3 DDP Export

**DDP 2.00 Compliant Export:**

```
DDP File Set:
├── DDPID (identifier)
├── DDPMS (main stream - audio)
├── PQDESCR (PQ descriptor)
├── SUBCODE (subcode data)
├── CDTEXT (CD-Text data)
└── MD5 checksum
```

**DDP Import:**
- Open DDP from other DAWs
- Verify checksums
- Edit after import
- Re-export modified

### 7.4 ISRC/UPC/EAN

```
Metadata Fields:
├── ISRC: XX-XXX-YY-NNNNN (per track)
│   ├── XX: Country code
│   ├── XXX: Registrant code
│   ├── YY: Year
│   └── NNNNN: Designation code
│
├── UPC/EAN: 12-13 digits (album)
└── MCN: Media Catalog Number
```

### 7.5 PQ Sheet

**Automatic PQ Sheet Generation:**
```
PQ Sheet Contents:
├── Track listing
├── Start times (frame-accurate)
├── Duration per track
├── ISRC codes
├── Total time
├── CD-Text preview
└── Export to PDF/Text
```

### 7.6 CD-Text

**CD-Text Fields:**
- Album title
- Artist name
- Track titles
- Track artists
- Composer
- Arranger
- Message
- Disc ID
- Genre
- UPC/EAN

### 7.7 Metadata Handling

**Metadata Preservation:**
```
Import:
├── BWF metadata
├── iXML
├── BEXT chunks
├── ID3 tags
└── CD-Text

Export:
├── Embed in output files
├── Sidecar files
├── DDP metadata
├── ADM metadata (Atmos)
└── Spreadsheet export
```

---

## 8. BROADCAST FEATURES

### 8.1 Loudness Compliance

**Supported Standards:**

| Standard | Target | True Peak | Region |
|----------|--------|-----------|--------|
| **EBU R128** | -23 LUFS | -1 dBTP | Europe |
| **ATSC A/85** | -24 LKFS | -2 dBTP | USA |
| **ARIB TR-B32** | -24 LKFS | -1 dBTP | Japan |
| **OP-59** | -24 LUFS | -2 dBTP | Australia |
| **AGCOM 219/09** | -24 LUFS | -2 dBTP | Italy |

### 8.2 True Peak Limiting

**Final Check Tool:**
```
True Peak Measurement:
├── 4x oversampling
├── Inter-sample peak detection
├── -1 dBTP compliance
├── Real-time display
└── History logging
```

### 8.3 LRA (Loudness Range)

```
LRA Guidelines:
├── Drama: 15-25 LU
├── Documentary: 10-15 LU
├── News: 5-10 LU
├── Music (classical): 20-30 LU
├── Music (pop): 5-10 LU
└── Commercials: <5 LU
```

### 8.4 Loudness Logging

**Final Check Logging:**
- Real-time loudness graph
- Export to file
- Historical comparison
- Multi-program analysis

### 8.5 MXF Support

**MXF (Material Exchange Format):**
- OP1a profile
- BWF audio within MXF
- Timecode preservation
- Metadata embedding
- SMPTE 382M audio

### 8.6 BWF/BEXT

**Broadcast Wave Format Extensions:**
```
BEXT Chunk Contents:
├── Description (256 chars)
├── Originator (32 chars)
├── OriginatorReference (32 chars)
├── OriginationDate (10 chars)
├── OriginationTime (8 chars)
├── TimeReference (64-bit sample count)
├── Version
├── UMID (Unique Material Identifier)
├── LoudnessValue
├── LoudnessRange
├── MaxTruePeakLevel
├── MaxMomentaryLoudness
└── MaxShortTermLoudness
```

### 8.7 Timecode

**Timecode Support:**

| Type | Support |
|------|---------|
| LTC (Linear) | Full |
| VITC (Vertical) | Full |
| MTC (MIDI) | Full |
| ATC (AES) | Via interface |
| PTP | Network |

**Frame Rates:**
- 23.976 fps (film pulldown)
- 24 fps (film)
- 25 fps (PAL)
- 29.97 fps (NTSC)
- 29.97 fps DF (drop-frame)
- 30 fps
- 48 fps
- 50 fps
- 59.94 fps
- 60 fps

**LTC Generator:**
- Output LTC from Pyramix
- Static or rolling
- Chase mode
- Free-run mode

---

## 9. NETWORK AUDIO

### 9.1 RAVENNA Native

**RAVENNA je Merging-ov IP audio protokol:**

```
RAVENNA Architecture:
┌─────────────────────────────────────────────────────────────────┐
│                    STUDIO NETWORK                                │
│                                                                  │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐                   │
│  │ Horus   │     │  Hapi   │     │ Anubis  │                   │
│  │ (48ch)  │     │ (16ch)  │     │  (4ch)  │                   │
│  └────┬────┘     └────┬────┘     └────┬────┘                   │
│       │               │               │                         │
│       └───────────────┼───────────────┘                         │
│                       │                                          │
│              ┌────────┴────────┐                                │
│              │   Gb Switch     │                                │
│              │   (managed)     │                                │
│              └────────┬────────┘                                │
│                       │                                          │
│              ┌────────┴────────┐                                │
│              │   Pyramix PC    │                                │
│              │   + MassCore    │                                │
│              └─────────────────┘                                │
└─────────────────────────────────────────────────────────────────┘
```

**RAVENNA Prednosti:**
- Bilo koji uređaj sluša bilo koji stream
- Dinamičko rutiranje
- Standard Ethernet infrastructure
- Scalable (100+ uređaja)

### 9.2 AES67 Compliance

**AES67 je subset RAVENNA:**

```
AES67 Profile:
├── Transport: RTP/UDP
├── Encoding: L16, L24 (uncompressed PCM)
├── Sample rates: 44.1, 48, 88.2, 96 kHz
├── Sync: PTPv2 (IEEE 1588-2008)
├── Discovery: SAP/SDP
└── Packet time: 1ms (48 samples @ 48kHz)
```

**Kompatibilnost:**
- Dante (AES67 mode)
- Livewire+
- Q-SYS
- Lawo
- Studer
- Stagetec

### 9.3 SMPTE ST2110

**ST2110 Broadcast Profile:**

```
ST2110 Suite:
├── ST2110-10: System timing (PTP)
├── ST2110-20: Uncompressed video
├── ST2110-21: Traffic shaping
├── ST2110-30: Audio (AES67)
├── ST2110-31: AES3 audio
└── ST2110-40: Ancillary data
```

Pyramix podržava **ST2110-30** za broadcast facility integraciju.

### 9.4 ANEMAN (Audio Network Manager)

```
ANEMAN Features:
├── Device discovery (Zeroconf/mDNS)
├── Visual connection matrix
├── Drag-and-drop routing
├── Status monitoring
├── Patch store/recall
├── Multi-manufacturer support
└── Free (no license fee)
```

### 9.5 Zeroconf/mDNS

**Automatic Discovery:**
- Devices announce themselves
- No manual IP configuration
- Instant visibility
- Works across subnets (with proper config)

### 9.6 PTP Sync (IEEE 1588)

```
PTP Hierarchy:
├── Grandmaster Clock (best clock wins)
├── Boundary Clocks (switches)
└── Slave Clocks (endpoints)

Best Master Clock Algorithm (BMCA):
├── Priority 1
├── Clock Class
├── Clock Accuracy
├── Clock Variance
├── Priority 2
└── Clock Identity
```

**Sync Accuracy:**
- < 1 microsecond typical
- Network-wide synchronization
- Automatic failover

---

## 10. METERING & VISUALIZATION

### 10.1 Multi-Channel Metering

**Meter Bridge:**
```
Meter Bridge Features:
├── All inputs display
├── All buses display
├── External sources
├── Configurable layout
├── Peak hold
├── VU/PPM/True Peak modes
├── Scalable UI
└── Separate window
```

### 10.2 Loudness Meters

**Final Check Tool (32-channel):**

```
Final Check Display:
┌─────────────────────────────────────────────────────────────────┐
│ Integrated:  -23.2 LUFS    [███████████░░░░░░░░░] -23 target   │
│ Short-term:  -21.5 LUFS    [█████████████░░░░░░░]              │
│ Momentary:   -18.3 LUFS    [███████████████░░░░░]              │
│ True Peak:   -1.2 dBTP     [██████████████████░░] -1 limit     │
│ LRA:         15.2 LU       [████████████████░░░░]              │
│                                                                  │
│ [History Graph - Time vs Loudness]                              │
└─────────────────────────────────────────────────────────────────┘
```

**Supported Formats:**
- Stereo
- 5.1
- 7.1
- 7.1.4 (Atmos)
- 9.1.6
- 22.2 (NHK)

### 10.3 Surround Scope

```
Surround Visualization:
├── Speaker position display
├── Energy distribution
├── Balance indicator
├── LFE level
├── Height layer display
└── Object positions (Atmos)
```

### 10.4 Correlation Meter

**Phase Correlation:**
```
Correlation Scale:
+1.0 ──── Mono (in phase)
 0.0 ──── Uncorrelated
-1.0 ──── Out of phase (cancel in mono)

Display:
├── L/R correlation
├── Per-channel pair
├── Historical average
└── Warning for <0 values
```

### 10.5 Spectrum Analyzer

**Real-time FFT:**
- Resolution up to 8192 points
- 60 fps update
- Logarithmic/linear scale
- Average/peak hold
- Reference curve overlay

### 10.6 History View

```
History Features:
├── Loudness over time
├── Peak history
├── Scrollable timeline
├── Zoom in/out
├── Export data
└── Multi-program view
```

---

## 11. UI/UX DESIGN

### 11.1 Virtual Studio Interface

**Main Window Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ [Menu Bar]  [Toolbars - customizable]                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │                    TIMELINE                              │   │
│  │                                                          │   │
│  │  Track 1: [====clip====][===clip===]                    │   │
│  │  Track 2: [======clip======]                            │   │
│  │  Track 3: [===][===][===][===]                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    MIXER                                 │   │
│  │  [Ch1][Ch2][Ch3]...[Master]                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ [Transport] [Time Display] [Status]                             │
└─────────────────────────────────────────────────────────────────┘
```

### 11.2 Mixer View

**Redesigned in Pyramix 15:**
- Scalable brightness (3 levels)
- Pinnable buses/strips
- Mini-graph EQ/dynamics visualization
- Compact/expanded modes
- Floating windows

### 11.3 Montage View

Za mastering — dedicated layout:
```
Montage View:
├── Track overview
├── CD track markers
├── Gap editor
├── Metadata panel
├── Output meters
└── Final Check integration
```

### 11.4 Media Browser

```
Media Browser Features:
├── Project media
├── Folder navigation
├── Search/filter
├── Preview playback
├── Drag to timeline
├── Metadata display
└── Missing media locator
```

### 11.5 Workspace Management

**Customization:**
- Save workspace layouts
- Keyboard shortcut sets
- Toolbar arrangements
- Window positions
- Multiple monitors
- Quick workspace switching

---

## 12. UNIQUE FEATURES

### 12.1 Only DAW with Native DSD Editing/Mixing

**Zašto je ovo važno:**

```
DSD Market:
├── High-end audiophiles
├── SACD production
├── Archival (analog-to-digital)
├── Purist classical labels
└── Premium streaming (NativeDSD, etc.)

Pyramix DSD Capabilities:
├── Record native DSD
├── Edit native DSD (with DXD bridge)
├── Mix native DSD
├── Master native DSD
├── Export SACD images
└── DSD scrubbing (!)
```

**Jedina alternativa:** Sony Sonoma (više se ne proizvodi)

### 12.2 MassCore (No Other DAW Has This!)

**MassCore Unique Value:**

| Feature | MassCore | Other DAWs |
|---------|----------|------------|
| Latency | ~1ms | 3-10ms |
| I/O @ 48kHz | 384 ch | 64-128 ch |
| OS Bypass | Yes | No |
| Real-time Guarantee | Yes | No |
| Network Native | RAVENNA | Via driver |

### 12.3 RAVENNA Native (IP Audio Pioneer)

**Merging je INVENTOR RAVENNA protokola:**
- First to market (2010)
- Influenced AES67 standard
- Influenced ST2110-30
- Still the reference implementation

### 12.4 Classical/Broadcast Industry Standard

**Market Position:**

```
Classical Recording:
├── 90%+ of major labels
├── Most concert halls
├── Most opera houses
├── Grammy-winning productions
└── Archival institutions

Broadcast:
├── BBC
├── European broadcasters
├── Sports events
├── Live concerts
└── Post-production houses
```

### 12.5 Why Pyramix Costs $8000+

**Justifikacija cene:**

1. **No Alternative:**
   - Native DSD: Only Pyramix
   - MassCore: Only Pyramix
   - 384 channels: Only Pyramix

2. **Total Cost of Ownership:**
   ```
   Pro Tools Ultimate: $2,499 + $599/year
   + HDX card: $7,999
   + I/O: $5,000+
   = $16,000+ first year

   Pyramix Premium: ~$8,000
   + Horus interface: ~$15,000
   = $23,000 (no recurring fees!)
   ```

3. **Reliability:**
   - Mission-critical recordings
   - No second chances (live concerts)
   - Broadcast uptime requirements

4. **Support:**
   - Direct from manufacturer
   - Long-term commitment
   - Regular updates

### 12.6 What FluxForge Can Learn from Pyramix

**Key Lessons:**

1. **Engine Architecture:**
   - Dedicated processing threads
   - OS bypass for audio
   - Predictable latency

2. **DSD Workflow:**
   - DXD bridge concept
   - Frame-accurate editing
   - SDM modulators

3. **Source/Destination Editing:**
   - Multi-window workflow
   - Multi-take management
   - Classical music optimization

4. **Network Audio:**
   - Native AES67 support
   - PTP synchronization
   - ANEMAN-style management

5. **Broadcast Features:**
   - Loudness compliance
   - Timecode integration
   - Metadata preservation

6. **Plugin Architecture:**
   - 32-channel plugins
   - Native sidechain
   - Massive PDC (23,000+ ms)

7. **Reliability:**
   - Backup recording paths
   - Keyboard lockout
   - Mission-critical design

---

## APPENDIX A: PYRAMIX SOFTWARE PACKS

### Pack Comparison

| Feature | Elements | Pro | Premium |
|---------|----------|-----|---------|
| **Price** | ~$1,500 | ~$4,000 | ~$8,000 |
| Playback Tracks | 512 | 512 | 512 |
| Hardware I/O | 48 | 96 | 128 |
| DSD/DXD Channels | 8 | 16 | 24 |
| Loudness Metering | No | Yes | Yes |
| Final Check | No | 8ch | **32ch** |
| Dolby Atmos ADM | No | No | **Yes** |
| VS3 Plugins | Basic | Standard | Full |
| Reverb | Session | Session | **Full** |
| CD/DDP | Basic | Yes | Yes |
| SACD | No | Yes | Yes |
| Ambisonic Order | 2nd | 3rd | **7th** |

### MassCore Add-on

**MassCore Pricing:**
- Standard: ~$2,500 (adds MassCore to any pack)
- Additional cores: ~$1,000 each

---

## APPENDIX B: PYRAMIX HARDWARE ECOSYSTEM

### Merging Interfaces

| Interface | I/O | Price | Best For |
|-----------|-----|-------|----------|
| **Horus** | 48in/32out | ~$15,000 | Large studios |
| **Hapi** | 8in/8out | ~$4,000 | Medium studios |
| **Anubis** | 4in/6out | ~$3,000 | Mobile/small |

**Sve interfejsi:**
- Native RAVENNA/AES67
- DSD support
- Premium preamps
- AD/DA conversion
- Word clock
- Remote control

---

## APPENDIX C: KONKURENTSKA ANALIZA

### Pyramix vs Pro Tools

| Aspect | Pyramix | Pro Tools |
|--------|---------|-----------|
| Latency | ~1ms | 3-10ms |
| Max I/O | 384 | 192 (HDX) |
| DSD | Native | Conversion only |
| Network Audio | Native | Via driver |
| Price | Higher | Lower entry |
| Market | Classical/Broadcast | Pop/Rock/Film |

### Pyramix vs Sequoia

| Aspect | Pyramix | Sequoia |
|--------|---------|---------|
| DSD | Native | No |
| MassCore | Yes | No |
| Source/Dest | Superior | Good |
| CD Mastering | Excellent | Excellent |
| Price | Higher | Similar |
| Market | Classical | Classical/Radio |

### Pyramix vs Nuendo

| Aspect | Pyramix | Nuendo |
|--------|---------|--------|
| DSD | Native | Limited |
| Surround | 22.2 native | 22.2 |
| Atmos | Excellent | Excellent |
| Video | Basic | Advanced |
| Price | Similar | Similar |
| Market | Audio-focused | Post-production |

---

## CONCLUSION

Pyramix 15 ostaje **neprikosnoven** u sledecim domenima:

1. **DSD produkcija** — Nema alternative
2. **Klasična muzika** — De facto standard
3. **High-channel-count broadcast** — 384 kanala
4. **Ultra-low latency** — MassCore
5. **Network audio** — RAVENNA pioneer

Za FluxForge, kljucne lekcije su:
- **Engine izolacija** od OS-a
- **DXD bridge** za DSD processing
- **Source/Destination** workflow
- **Native AES67** networking
- **Mission-critical reliability**

---

## IZVORI

- [Merging Technologies - Pyramix MassCore](https://www.merging.com/products/pyramix/masscore-native)
- [Merging Technologies - Pyramix Key Features](https://www.merging.com/products/pyramix/key-features)
- [Merging Technologies - Pyramix Overview](https://www.merging.com/products/pyramix)
- [Merging Technologies - RAVENNA Networking](https://www.merging.com/products/pyramix/ravenna)
- [Merging Technologies - VS3 & VST Plugins](https://www.merging.com/products/pyramix/vs3-vst-plugins)
- [Production Expert - Why Classical Engineers Choose Pyramix](https://www.production-expert.com/production-expert-1/why-some-classical-recording-engineers-choose-pyramix-over-pro-tools)
- [Merging Technologies DSD-DXD Production Guide](https://www.merging.com/uploads/assets/Merging_pdfs/Merging_Technologies_DSD-DXD_Production_Guide.pdf)
- [RAVENNA Network Standards Comparison](https://www.ravenna-network.com/overview/standards-comparison/)
- [EBU R128 Loudness Standard](https://tech.ebu.ch/docs/r/r128.pdf)
- [b<>com HOA Plugins for Pyramix](https://merging.atlassian.net/wiki/spaces/PUBLICDOC/pages/4817118/Bcom+plugins)

---

*Dokument kreiran: Januar 2025*
*Za FluxForge Studio research*
