# LOGIC PRO — ULTRA DETALJNA ANALIZA
## Verzija: Logic Pro 11.x (2024-2026)

---

## 1. AUDIO ENGINE ARCHITECTURE

### 1.1 CoreAudio Integracija

Logic Pro koristi **CoreAudio** — native macOS audio framework za low-latency audio I/O:

| Karakteristika | Specifikacija |
|----------------|---------------|
| **Audio API** | CoreAudio (native macOS) |
| **Driver Model** | HAL (Hardware Abstraction Layer) |
| **Latencija** | < 3ms @ 128 samples |
| **Thread Safety** | Real-time safe callbacks |
| **Aggregate Devices** | Podržano (kombinovanje interfejsa) |

### 1.2 Sample Rates (Podržani)

| Sample Rate | Namena |
|-------------|--------|
| **44.1 kHz** | CD kvalitet, muzička produkcija |
| **48 kHz** | Video/Film standard, broadcast |
| **88.2 kHz** | High-res (2x 44.1) |
| **96 kHz** | High-res video/mastering |
| **176.4 kHz** | Quad-rate (4x 44.1) |
| **192 kHz** | Maximum kvalitet, mastering |

**Napomena:** Logic Pro NE podržava 384kHz — maksimum je 192kHz.

### 1.3 Bit Depth (Interna preciznost)

| Tip | Specifikacija |
|-----|---------------|
| **Snimanje** | 16-bit ili 24-bit (default: 24-bit) |
| **Interna obrada** | 32-bit floating point |
| **64-bit sumiranje** | Da (mixer summing) |
| **Dithering** | POW-r algoritmi za finalni output |

### 1.4 Buffer Sizes

#### I/O Buffer Size
Kontroliše latenciju ulaza/izlaza:

| Buffer Size | Latency @ 44.1kHz | Upotreba |
|-------------|-------------------|----------|
| **32 samples** | ~0.7ms | Ultra-low latency recording |
| **64 samples** | ~1.5ms | Live recording |
| **128 samples** | ~2.9ms | Standard recording |
| **256 samples** | ~5.8ms | Recording sa plugin-ima |
| **512 samples** | ~11.6ms | Mixing |
| **1024 samples** | ~23.2ms | Heavy mixing |
| **2048 samples** | ~46.4ms | Mastering |

#### Process Buffer Range
Dodatni buffer za DSP procesiranje:

| Opcija | Efekat |
|--------|--------|
| **Small** | Minimalna latencija, veće CPU opterećenje |
| **Medium** | Balans performansi |
| **Large** | Maksimalna efikasnost, veća latencija |

### 1.5 Multi-threading (Thread Priority)

| Parametar | Opis |
|-----------|------|
| **Processing Threads** | Automatski = broj CPU jezgara |
| **Manual Override** | Moguće specificirati broj thread-ova |
| **Multithreading Mode** | Playback vs. Live Tracks |
| **Active Threads Display** | Real-time monitoring u CPU metru |

**Best Practice:**
- Ako system overload koincidira sa Processing Threads metrima → koristi "Active" opciju
- Ako koincidira sa Drive I/O → isključi multithreading

### 1.6 Plugin Latency Compensation (PDC)

Logic Pro ima automatsku kompenzaciju latencije plugin-a:

| Režim | Opis |
|-------|------|
| **Audio and Software Instrument Tracks** | Kompenzuje samo audio/instrument kanale |
| **All** | Kompenzuje SVE kanale (uključujući Aux/Output) — za mixing |

**Low Latency Mode:**
- Bypassa plugin-e sa velikom latencijom tokom snimanja
- **Limit slider** — maksimalna dozvoljena latencija (ms)
- Automatski bypassa plugin-e koji prelaze limit

**Recording Delay Compensation:**
- Kompenzuje fiksnu latenciju audio drivera
- Obično nije potrebno podešavati ručno

### 1.7 Freeze Track Implementation

| Karakteristika | Opis |
|----------------|------|
| **Freeze Source** | Pre ili Post Fader |
| **Freeze Quality** | Source (offline bounce) |
| **CPU Savings** | Oslobađa DSP resurse |
| **Edit Capability** | Unfreeze za editovanje |
| **Automation** | Zamrzava sa automatizacijom |

---

## 2. DSP PROCESSORS (STOCK PLUGINS)

### 2.1 EQUALIZERI

#### Channel EQ (8-band + Analyzer)

| Specifikacija | Vrednost |
|---------------|----------|
| **Broj bendova** | 8 |
| **Filter tipovi** | Low Cut, Low Shelf, 4x Parametric Bell, High Shelf, High Cut |
| **Frequency range** | 20 Hz — 20 kHz |
| **Gain range** | ±24 dB |
| **Q range** | 0.1 — 100 |
| **Analyzer** | Real-time FFT (Pre ili Post EQ) |
| **CPU Usage** | Vrlo nizak |
| **Phase Mode** | Minimum phase |

#### Linear Phase EQ

| Specifikacija | Vrednost |
|---------------|----------|
| **Broj bendova** | 8 (identično Channel EQ) |
| **Fase karakteristika** | Zero phase shift |
| **CPU Usage** | Konstantan (nezavisno od broja aktivnih bendova) |
| **Latency** | Značajna (za mastering) |
| **Primena** | Transparent editing, mastering |
| **Interoperabilnost** | Copy/paste settings sa Channel EQ |

#### Vintage EQ Collection (4 modela)

##### Vintage Console EQ (Neve 1073 stil)
| Karakteristika | Specifikacija |
|----------------|---------------|
| **Originalni hardware** | Neve 1073 (1970, Rupert Neve) |
| **Low Cut** | 50-300 Hz (3rd order passive) |
| **Low Freq** | 35-220 Hz (shelf) |
| **High Freq** | Fixed 12 kHz shelf |
| **Mid EQ** | Selectable frequencies |
| **Drive** | Analog-style saturation |
| **Output Models** | Silky, Smooth, Punchy |
| **Phase Modes** | Natural, Linear |

##### Vintage Graphic EQ (API 560 stil)
| Karakteristika | Specifikacija |
|----------------|---------------|
| **Originalni hardware** | API 560 |
| **Broj bendova** | 10 |
| **Tip** | Graphic EQ |
| **Boost/Cut** | Per-band |
| **Character** | Punchy, aggressive |

##### Vintage Tube EQ (Pultec EQP-1A stil)
| Karakteristika | Specifikacija |
|----------------|---------------|
| **Originalni hardware** | Pultec EQP-1A + MEQ-5 |
| **Tip** | Passive tube EQ |
| **Character** | Warm, musical |
| **Low Boost/Atten** | Simultaneous (Pultec trick) |

##### Common Vintage EQ Features
| Feature | Opis |
|---------|------|
| **Phase Modes** | Natural (analog-like) ili Linear |
| **Drive** | Per-plugin saturation |
| **Output Volume** | ±25 dB |

---

### 2.2 KOMPRESORI

#### Logic Compressor — 7 Circuit Types

| Model | Inspiracija | Karakteristika |
|-------|-------------|----------------|
| **Platinum Digital** | Logic original | Clean, transparent, fast transients |
| **Studio VCA** | Focusrite Red 3 | Fast, tight, clean — bus compression |
| **Studio FET** | UREI 1176 Blackface | Fast compression, less saturation |
| **Classic VCA** | DBX 160 | Fire-and-forget, auto attack/release |
| **Vintage VCA** | SSL G Bus Compressor | Glue effect, drum bus |
| **Vintage FET** | 1176 Silverface/Bluestripe | Aggressive, saturated |
| **Vintage Opto** | Teletronix LA-2A | Slow, musical, smooth |

#### Detaljne specifikacije po tipu:

##### FET Kompresori (Studio/Vintage)
| Parametar | Specifikacija |
|-----------|---------------|
| **Attack** | Ultra-fast (< 1ms moguć) |
| **Gain Reduction** | Only attenuation (no makeup) |
| **Character** | Midrange warmth, punch |
| **Best for** | Drums, vocals, guitars |

##### VCA Kompresori (Studio/Classic/Vintage)
| Parametar | Specifikacija |
|-----------|---------------|
| **Attack range** | Fast to slow |
| **Character** | Clean, precise |
| **Best for** | Bass, mix bus, mastering |
| **Classic VCA Special** | Full auto attack/release |

##### Opto Kompresor (Vintage Opto)
| Parametar | Specifikacija |
|-----------|---------------|
| **Detection** | Light-dependent resistor emulation |
| **Attack** | Program-dependent (slow) |
| **Release** | Program-dependent |
| **Character** | Gentle, transparent |
| **Best for** | Vocals, acoustic instruments |

#### Multipressor (Multiband Compressor)

| Specifikacija | Vrednost |
|---------------|----------|
| **Broj bendova** | 4 |
| **Per-band controls** | Threshold, Ratio, Attack, Release, Gain |
| **Crossover** | Adjustable frequency points |
| **Default Threshold** | -15 dB |
| **Default Ratio** | 3:1 |
| **Metering** | Per-band gain reduction |
| **Primena** | Mastering, problem solving |

#### Limiter (Peak Limiter)

| Specifikacija | Vrednost |
|---------------|----------|
| **Ratio** | Infinity:1 (brick wall) |
| **Character** | Transparent |
| **Look-ahead** | Ne |
| **Primena** | Preventing clipping |

#### Adaptive Limiter

| Specifikacija | Vrednost |
|---------------|----------|
| **Ratio** | Infinity:1 |
| **Character** | Adaptive, colored |
| **Look-ahead** | Da (adjustable) |
| **Modes** | OptFit (allows peaks), NoOver (true peak limiting) |
| **Remove DC** | Highpass filter option |
| **Primena** | Final limiting, mastering |

**Napomena:** Dodaje latenciju — za mixing/mastering, ne za recording.

---

### 2.3 REVERB EFEKTI

#### Space Designer (Convolution Reverb)

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Convolution (IR-based) |
| **IR Support** | Load custom impulse responses |
| **IR Synthesis** | Built-in IR creation |
| **Modes** | Mono, Stereo, True Stereo, Surround |
| **Envelope** | ADSR-style control |
| **Filter** | HP, LP, BP (6dB, 12dB slopes) |
| **Output EQ** | 4-band parametric |
| **Stereo Balance** | Full control |
| **Automation** | Limited (requires IR reload) |

**IR Library:** Prostori, plate reverbs, halls, rooms, springs

#### ChromaVerb (Algorithmic Reverb)

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Algorithmic |
| **Room Types** | Hall, Room, Chamber, Concert Hall, Dense, Strange |
| **Controls** | Size, Decay, Predelay, Distance |
| **Damping EQ** | Frequency-dependent decay |
| **Modulation** | Speed, Depth |
| **Width** | Stereo spread control |
| **Early/Late Balance** | Adjustable |
| **Visualization** | Animated graphic |

**Best for:** Synth pads, wide reverbs, creative effects

#### Quantec Room Simulator (NOVO — Logic Pro 11.1)

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Authentic recreation |
| **Original Hardware** | Quantec QRS (1982) + YardStick |
| **Algorithms** | Original Wolfgang Buchleitner code |
| **Modes** | QRS (Vintage), YardStick (Modern) |
| **Special Feature** | Freeze (infinite reverb layering) |
| **Correlation** | Stereo width control |
| **First Reflection Spread** | Early reflection stereo width |
| **Subsonic Filter** | Low frequency cleanup |
| **Zahtevi** | macOS Sonoma 14.4+ |

#### Vintage Reverbs

| Plugin | Tip | Character |
|--------|-----|-----------|
| **SilverVerb** | Simple algorithmic | Vintage digital |
| **PlatinumVerb** | Enhanced algorithmic | Lush, smooth |
| **EnVerb** | Envelope-controlled | Gated reverb |

---

### 2.4 DELAY EFEKTI

#### Stereo Delay

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Digital stereo delay |
| **Channels** | Independent L/R |
| **Tempo Sync** | Da |
| **Feedback** | Per-channel + crossfeed |
| **Ping-Pong** | Da |
| **Filter** | HP/LP in feedback loop |
| **Deviation** | L/R offset |

#### Tape Delay

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Vintage tape echo emulation |
| **Tempo Sync** | Da |
| **Filter** | HP/LP in feedback |
| **Flutter Rate** | Tape speed variation |
| **Flutter Intensity** | Amount of wow/flutter |
| **LFO Rate** | Modulation speed |
| **LFO Intensity** | Chorus-like modulation |
| **Tape Head Mode** | Clean, Diffuse |
| **Freeze** | Infinite sustain |

**Best for:** Dub delays, vintage sound, creative effects

#### Echo

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip** | Simple tempo-synced delay |
| **Interface** | Minimal |
| **Feedback** | Single control |
| **Color** | Frequency tilt |
| **Best for** | Quick, simple delays |

#### Sample Delay

| Specifikacija | Vrednost |
|---------------|----------|
| **Max delay** | 250ms |
| **Resolution** | Sample-accurate |
| **L/R Independent** | Da |
| **Mode** | Samples ili Milliseconds |
| **Primena** | Phase alignment, mic placement emulation |

**Formula:** @ 44.1kHz, 1 sample = 7.76mm acoustic distance
**Example:** 13 samples = ~10cm mic separation

---

### 2.5 MODULATION EFEKTI

#### Chorus

| Parametar | Specifikacija |
|-----------|---------------|
| **Delay Range** | 10-40ms (chorus sweet spot) |
| **LFO** | Rate control |
| **Mix** | Wet/Dry blend |
| **Character** | Warmth, width |

#### Ensemble

| Parametar | Specifikacija |
|-----------|---------------|
| **Voices** | Up to 8 |
| **LFOs** | 2 sine + 1 random |
| **Spread** | Stereo distribution |
| **Character** | Deep, rich chorus |

#### Flanger

| Parametar | Specifikacija |
|-----------|---------------|
| **Delay** | Very short (<10ms) |
| **Feedback** | Positive/Negative |
| **LFO** | Sweeping modulation |
| **Character** | Jet/underwater effect |

#### Phaser

| Parametar | Specifikacija |
|-----------|---------------|
| **Stages** | Multiple allpass filters |
| **LFOs** | 2 independent |
| **Ceiling/Floor** | Frequency range |
| **Envelope Follower** | Dynamic control |
| **Character** | Sweeping, notchy |

#### Tremolo

| Parametar | Specifikacija |
|-----------|---------------|
| **Tip** | Amplitude modulation |
| **Tempo Sync** | Da |
| **Rate** | Rhythmic subdivisions |
| **Depth** | Modulation amount |

#### Spreader

| Parametar | Specifikacija |
|-----------|---------------|
| **Tip** | Stereo enhancement |
| **Method** | Phase/delay manipulation |
| **Primena** | Widening mono sources |

---

### 2.6 SATURATION / DISTORTION

#### ChromaGlow (NOVO — Logic Pro 11)

| Specifikacija | Vrednost |
|---------------|----------|
| **Zahtevi** | Apple Silicon (M1+) |
| **Saturation Models** | 5 |
| **Drive Range** | Subtle to aggressive |
| **Bypass Below** | Frequency threshold |
| **Low Cut** | 6-48 dB/octave slopes |
| **Resonant Shaper** | Unique feature |

##### ChromaGlow Saturation Models:

| Model | Inspiracija | Character |
|-------|-------------|-----------|
| **Retro Tube** | Vintage tube amps | Warm, slightly muddy |
| **Modern Tube** | Contemporary tube | Clean with warmth |
| **Magnetic** | Tape saturation | Warm, transformer color |
| **Squeeze** | Pushed compressor | Soft/Hard press options |
| **Analog Preamp** | Transistor preamp | Sharp, edgy, punchy |

#### Overdrive

| Parametar | Specifikacija |
|-----------|---------------|
| **Tip** | Tube-style overdrive |
| **Drive** | Amount of saturation |
| **Tone** | EQ control |
| **Output** | Level compensation |

#### Distortion

| Parametar | Specifikacija |
|-----------|---------------|
| **Tip** | Hard clipping |
| **Drive** | Intensity |
| **Tone** | Pre/Post EQ |

#### Bitcrusher

| Parametar | Specifikacija |
|-----------|---------------|
| **Resolution** | Bit depth reduction |
| **Downsampling** | Sample rate reduction |
| **Character** | Lo-fi, digital artifacts |

---

## 3. MIXER ARCHITECTURE

### 3.1 Channel Strip Signal Flow

```
INPUT (Audio/Instrument)
    ↓
┌─────────────────────────────────────────────┐
│ MIDI FX (instruments only) — up to 8 slots  │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ INSTRUMENT (software instrument slot)       │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ INPUT GAIN (Gain plugin or channel input)   │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ AUDIO FX INSERTS — 15 slots                 │
│ ├── Slot 1                                  │
│ ├── Slot 2                                  │
│ ├── ...                                     │
│ └── Slot 15                                 │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ SENDS — 8 sends (Pre/Post Fader)            │
│ ├── Send 1 → Aux Bus                        │
│ ├── Send 2 → Aux Bus                        │
│ ├── ...                                     │
│ └── Send 8 → Aux Bus                        │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ PAN (Stereo Panner ili Surround Panner)     │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ FADER (Volume control)                      │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│ OUTPUT (Bus, Output, Surround)              │
└─────────────────────────────────────────────┘
```

### 3.2 Insert Slots

| Specifikacija | Vrednost |
|---------------|----------|
| **Broj insert slotova** | 15 po kanalu |
| **Plug-in tipovi** | Audio Units (AU) |
| **Sidechain** | Podržano |
| **A/B Comparison** | Ne (potreban workaround) |
| **Drag & Reorder** | Da |
| **Copy/Paste** | Da |

### 3.3 Send Slots

| Specifikacija | Vrednost |
|---------------|----------|
| **Broj send slotova** | 8 po kanalu |
| **Routing** | Pre-Fader ili Post-Fader |
| **Level Control** | Per-send |
| **Destination** | Aux channel strips |
| **Panning** | Follows channel pan ili Independent |

### 3.4 Channel Strip Types

| Tip | Namena |
|-----|--------|
| **Audio** | Audio recording/playback |
| **Software Instrument** | Virtual instruments (MIDI input) |
| **External MIDI** | External hardware synths |
| **Aux** | Returns, submixes, routing |
| **Output** | Physical outputs (interface) |
| **VCA** | Volume control automation |
| **Master** | Global output control |

### 3.5 Bus Architecture

| Element | Opis |
|---------|------|
| **Internal Buses** | 256+ available |
| **Naming** | Custom names |
| **Creation** | Automatic kada se send/output postavi |
| **Aux Auto-Creation** | Da — automatski kreira Aux kada se bus koristi |

### 3.6 Track Stacks

#### Summing Stack
| Karakteristika | Opis |
|----------------|------|
| **Funkcija** | Audio submix/grouping |
| **Signal Flow** | Subtracks → Bus → Stack Master |
| **Processing** | Na Stack Master kanalu |
| **Use Case** | Drum bus, vocal stack |

#### Folder Stack
| Karakteristika | Opis |
|----------------|------|
| **Funkcija** | Organization only |
| **Signal Flow** | Individual outputs preserved |
| **Processing** | Per-track (no master processing) |
| **Use Case** | Organizing large projects |

### 3.7 VCA Groups

| Karakteristika | Opis |
|----------------|------|
| **Signalni put** | NEMA — samo kontrolni signal |
| **Fader behavior** | Kontroliše volume assigned kanala |
| **Metering** | Nema (nema signala) |
| **Inserts/Sends** | Nema (nema signala) |
| **Automation** | Da — automatizacija ide na VCA |
| **Post-fader sends** | Prate VCA volume changes |
| **Prednost** | Manje CPU nego Aux submix |

**Use Cases:**
- Drum group control
- Vocal ensemble
- Orchestra sections
- Stems automation

### 3.8 Output Channels

| Karakteristika | Opis |
|----------------|------|
| **Broj** | Zavisi od audio interface-a |
| **Stereo Output** | Default main output |
| **Surround Outputs** | Do 7.1.4 za Atmos |
| **Inserts** | 15 slots (mastering chain) |

### 3.9 Master Channel

| Karakteristika | Opis |
|----------------|------|
| **Funkcija** | Global gain za SVE outputs |
| **Scaling** | Proporcionalno skalira sve outpute |
| **Use Case** | Quick global level adjustment |

---

## 4. SURROUND & SPATIAL AUDIO

### 4.1 Surround Formats

| Format | Channels | Opis |
|--------|----------|------|
| **Stereo** | 2.0 | Standard L/R |
| **5.1** | 6 | L, C, R, Ls, Rs, LFE |
| **7.1** | 8 | + Lss, Rss |
| **7.1.2** | 10 | + Ltf, Rtf (top front) |

### 4.2 Dolby Atmos

| Specifikacija | Vrednost |
|---------------|----------|
| **Project Format** | 7.1.2 (bed) |
| **Object Tracks** | Up to 118 |
| **Monitoring** | Up to 7.1.4 |
| **Frame Rate** | 24 fps (required) |
| **Sample Rate** | 48 kHz ili 96 kHz (recommended) |
| **I/O Buffer** | 512 (48k) ili 1024 (96k) |
| **Target Loudness** | ≤ -18 LUFS |
| **Export Format** | ADM BWF |

#### Bed vs Objects
| Tip | Opis |
|-----|------|
| **Bed** | Fixed 7.1.2 surround mix |
| **Objects** | Position-able audio sources |
| **Height info** | Beyond 7.1.2 = must use objects |

#### Monitoring Formats
- 5.1.2
- 5.1.4
- 7.1.4 (recommended)
- Binaural (headphones)

---

## 5. TIMELINE / ARRANGEMENT

### 5.1 Main Window (Tracks Area)

| Element | Opis |
|---------|------|
| **Tracks** | Vertical lanes za audio/MIDI |
| **Regions** | Audio/MIDI clips on timeline |
| **Playhead** | Current position indicator |
| **Ruler** | Time/Bar:Beat display |
| **Cycle** | Loop region |
| **Locators** | Punch in/out points |

### 5.2 Track Types

| Tip | Namena |
|-----|--------|
| **Audio** | Recording/playback audio |
| **Software Instrument** | MIDI → Virtual instrument |
| **Drummer** | AI drum performance |
| **External MIDI** | Hardware synths |
| **Aux** | Returns, routing |
| **Output** | Physical outputs |
| **VCA** | Group volume control |

### 5.3 Region Types

| Tip | Sadržaj |
|-----|---------|
| **Audio Region** | Waveform data |
| **MIDI Region** | Note/CC data |
| **Pattern Region** | Step Sequencer pattern |
| **Drummer Region** | AI drum pattern |
| **Alias** | Reference to another region |

### 5.4 Fades & Crossfades

| Tip | Opis |
|-----|------|
| **Fade In** | Linear, S-Curve, Slow, Fast |
| **Fade Out** | Linear, S-Curve, Slow, Fast |
| **Crossfade** | Automatic overlap handling |
| **Speed** | Draggable fade handles |

### 5.5 Automation Modes

| Mode | Ponašanje |
|------|-----------|
| **Read** | Playback samo — ne može se menjati kontrolama |
| **Touch** | Write while touching → return to existing |
| **Latch** | Write while touching → stay at new value |
| **Write** | Continuous writing (destructive) |
| **Trim** | Offset existing automation (+/- adjustment) |
| **Relative** | Secondary curve that offsets primary |

#### Automation Parameters
- Volume, Pan, Sends (channel strip)
- Any plug-in parameter
- MIDI CC (via automation)

### 5.6 Smart Tempo

| Mode | Ponašanje |
|------|-----------|
| **Keep Project Tempo** | Project tempo stays fixed |
| **Adapt Project Tempo** | Project follows recording/import |
| **Automatic** | Context-aware (metronome = keep, no ref = adapt) |

#### Flex & Follow Settings
| Setting | Opis |
|---------|------|
| **Off** | No tempo following |
| **On** | Follow tempo (no beat flex) |
| **Bars** | Align at bar level |
| **Beats** | Align at beat level |

#### Tempo Detection
| Mode | Best For |
|------|----------|
| **Variable** | Live recordings without click |
| **Constant** | Recordings with click/drum machine |

### 5.7 Markers

| Tip | Opis |
|-----|------|
| **Standard Markers** | Labeled positions |
| **Arrangement Markers** | Section markers (verse, chorus) |
| **Movie Markers** | Video sync points |

### 5.8 Movie Track

| Karakteristika | Opis |
|----------------|------|
| **Formats** | QuickTime compatible |
| **Display** | Thumbnail strip |
| **Sync** | Frame-accurate |
| **Timecode** | SMPTE display |

---

## 6. LIVE LOOPS

### 6.1 Grid Architecture

| Element | Opis |
|---------|------|
| **Grid** | Rows (tracks) × Columns (scenes) |
| **Rows** | Linked to track channel strips |
| **Columns** | Scenes (vertical groups) |
| **Cells** | Individual loop containers |

### 6.2 Cell Types

| Tip | Sadržaj |
|-----|---------|
| **Audio Cell** | Audio loop |
| **MIDI Cell** | MIDI pattern |
| **Pattern Cell** | Step Sequencer pattern |
| **Drummer Cell** | AI drum pattern |

### 6.3 Cell Parameters

| Parametar | Opis |
|-----------|------|
| **Loop Length** | Cell duration |
| **Playback Mode** | Loop, One-shot, etc. |
| **Quantize Start** | When cell begins |
| **Play From** | Start position |
| **Tempo** | Cell-specific tempo |

### 6.4 Scene Triggering

| Metod | Opis |
|-------|------|
| **Click** | Scene trigger button |
| **MIDI** | Note-based triggering |
| **Key Command** | Keyboard shortcuts |
| **iPad/Remote** | Touch triggering |

### 6.5 Arrangement Integration

| Feature | Opis |
|---------|------|
| **Record Performance** | Capture to Tracks area |
| **Drag & Drop** | Copy cells to timeline |
| **Scene Insert** | Insert scene as arrangement |
| **Divider Column** | Switch between grid/tracks |

**Important:** Samo jedna source po track-u — cell ILI region, nikad oba istovremeno.

---

## 7. EDITING CAPABILITIES

### 7.1 Flex Time Algorithms

| Algorithm | Best For | Special Features |
|-----------|----------|------------------|
| **Slicing** | Drums/Percussion | Cuts at transients, no stretch |
| **Rhythmic** | Loops, rhythmic material | Time-stretch with transient preservation |
| **Monophonic** | Solo vocals, mono instruments | Pitch preservation for melodic content |
| **Polyphonic** | Chords, complex material | Phase vocoding, CPU intensive |
| **Tempophone (FX)** | Sound design | Granular-style artifacts |
| **Speed (FX)** | Varispeed effect | Pitch follows speed |

#### Monophonic Parameters
| Parametar | Opis |
|-----------|------|
| **Percussive** | ON = preserve transients (plucked strings) |
| **Percussive OFF** | Smoother (bowed strings, winds) |

#### Polyphonic Parameters
| Parametar | Opis |
|-----------|------|
| **Complex** | More internal transients |

### 7.2 Flex Pitch

| Specifikacija | Vrednost |
|---------------|----------|
| **Tip materijala** | Monophonic only |
| **Detection** | Automatic pitch analysis |
| **Note Editing** | Drag notes vertically |
| **Fine Tune** | Per-note cents adjustment |
| **Vibrato** | Amount control |
| **Gain** | Per-note volume |
| **Formant Tracking** | Adjustable interval |
| **Formant Shift** | Preserve character |
| **Drift** | Pitch stability |

### 7.3 Quick Sampler

| Feature | Opis |
|---------|------|
| **Modes** | Classic, One Shot, Slice, Recorder |
| **Slicing** | Transient-based automatic |
| **Pitch Detection** | Root note identification |
| **ADSR** | Envelope shaping |
| **Filter** | LP, HP, BP |
| **LFO** | Modulation source |

### 7.4 Sample Alchemy

| Feature | Opis |
|---------|------|
| **Sources** | 4 independent (A, B, C, D) |
| **Synthesis Types** | Granular, Additive, Spectral |
| **Morphing** | Between sources |
| **Playback Modes** | Scrub, Bow, Loop |

#### Granular Parameters
| Parametar | Opis |
|-----------|------|
| **Size** | 2-230ms grain duration |
| **Density** | Grain overlap |
| **Random Pan/Time** | Variation |
| **Position** | Playback point |
| **Freeze** | Infinite drone |

**System Requirements:** M1+ Apple Silicon

### 7.5 Step Sequencer

| Feature | Opis |
|---------|------|
| **Pattern Length** | Default 16, adjustable |
| **Step Rate** | Per-pattern or per-row |
| **Playback Modes** | Forward, Reverse, Ping-pong, Random |
| **Per-row Length** | Independent loop lengths |
| **Subrows** | Velocity, Gate, Note, Octave, Repeat |
| **Note Repeat** | Ratcheting effect |
| **Scale Quantize** | Key + scale lock |
| **Live Recording** | Real-time pattern capture |
| **Melodic Mode** | Note grid (pitch rows) |

---

## 8. MIDI CAPABILITIES

### 8.1 Editors

| Editor | Namena |
|--------|--------|
| **Piano Roll** | Note editing (velocity, length, position) |
| **Step Editor** | Grid-based event editing |
| **Score Editor** | Traditional notation |
| **Event List** | Text-based MIDI editing |

### 8.2 MIDI Transform

| Funkcija | Opis |
|----------|------|
| **Presets** | Fixed Velocity, Humanize, etc. |
| **Custom** | User-defined transformations |
| **Conditions** | IF-THEN logic |
| **Operations** | Add, Multiply, Scale, etc. |

### 8.3 MIDI FX Plugins (8 slots per channel)

#### Arpeggiator
| Feature | Opis |
|---------|------|
| **Patterns** | Up, Down, Up/Down, Random, As Played |
| **Rate** | 1/1 to 1/128 (+ triplets) |
| **Octave Range** | Multi-octave expansion |
| **Latch** | Sustain modes (Reset, Transpose) |
| **Keyboard Split** | Zones for control/arpeggiate/lead |
| **Remote** | MIDI control mapping |

#### Chord Trigger
| Feature | Opis |
|---------|------|
| **Single Mode** | One key → chord |
| **Multi Mode** | Custom chord per key |
| **Learn** | Teach custom chords |

#### Scripter
| Feature | Opis |
|---------|------|
| **Language** | JavaScript |
| **Functions** | HandleMIDI, ProcessMIDI |
| **Capabilities** | Generate, transform, filter MIDI |
| **Presets** | Harpeggiator, Chord Strummer, etc. |

#### Other MIDI FX
- **Note Repeater** — Delay-style note echo
- **Transposer** — Pitch shift/scale
- **Velocity Processor** — Dynamics control
- **Modulator** — LFO → CC
- **Modifier** — CC transformation

### 8.4 Articulation Management

| Feature | Opis |
|---------|------|
| **Articulation Sets** | Per-track articulation mapping |
| **Articulation ID** | Per-note assignment |
| **Key Switches** | Automatic management |
| **Smart Controls** | Articulation switching UI |

---

## 9. PLUGIN HOSTING

### 9.1 Supported Formats

| Format | Support |
|--------|---------|
| **Audio Units (AU)** | Native — full support |
| **AU Instruments** | Multi-output support |
| **VST3** | NE — samo AU |
| **AAX** | NE — samo AU |

### 9.2 ARA2 Support

| Feature | Opis |
|---------|------|
| **Compatible Plugins** | Melodyne, SpectraLayers |
| **Integration** | Direct timeline access |
| **Region-based** | Edits follow region moves |
| **Insert Position** | First Audio FX slot |
| **Flex Conflict** | ARA disables Flex |

### 9.3 Plugin Manager

| Feature | Opis |
|---------|------|
| **Scanning** | Automatic at launch |
| **AU Validation** | Apple AU validation |
| **Enable/Disable** | Per-plugin control |
| **Categories** | Custom organization |
| **Reset** | Force re-scan |

### 9.4 Plugin Delay Compensation

| Setting | Opis |
|---------|------|
| **Audio & Instruments** | Compensate track latency only |
| **All** | Compensate aux/output latency too |
| **Low Latency Mode** | Bypass high-latency plugins |
| **Latency Display** | Hover over plugin → samples/ms |

---

## 10. PROJECT MANAGEMENT

### 10.1 Project Packaging

| Option | Opis |
|--------|------|
| **Project Package** | .logicx bundle (self-contained) |
| **Project Folder** | Separate assets folder |
| **Copy Audio** | Include used audio files |
| **Copy Movie** | Include video files |

### 10.2 Project Alternatives

| Feature | Opis |
|---------|------|
| **Purpose** | Snapshot versions within single project |
| **Shared Assets** | Audio files shared between alternatives |
| **Use Cases** | Different mixes, arrangements, cuts |
| **Limit** | 10 backups per alternative |
| **Location** | File > Project Alternatives submenu |

### 10.3 Track Alternatives

| Feature | Opis |
|---------|------|
| **Purpose** | Multiple arrangements per track |
| **Channel Strip** | Shared (same settings) |
| **Content** | Different regions/takes |
| **Comping** | Create comp from alternatives |
| **Preview** | Hear inactive alternative in context |
| **Grouping** | Works with Track Groups |

### 10.4 Backups

| Feature | Opis |
|---------|------|
| **Automatic** | On each save (Cmd+S) |
| **Limit** | 10 per alternative |
| **Access** | File > Revert to |
| **Ordering** | Newest to oldest |

### 10.5 Selection-Based Processing

| Feature | Opis |
|---------|------|
| **Apply** | Effects to selected audio |
| **Non-destructive** | Creates new region |
| **Preview** | Audition before commit |
| **Undo** | Full undo support |

### 10.6 Bounce Options

| Type | Opis |
|------|------|
| **Bounce Project** | Full mix to file |
| **Bounce in Place** | Selected region → audio |
| **Bounce Track in Place** | Track → audio track |
| **Bounce All Tracks** | Stems export |

#### Bounce Settings
| Option | Choices |
|--------|---------|
| **Format** | WAV, AIFF, MP3, M4A, FLAC |
| **Bit Depth** | 16, 24, 32 float |
| **Sample Rate** | Project or custom |
| **Dithering** | None, POW-r types |
| **Normalize** | Off, Overload Only, On |
| **Surround** | Interleaved or Split |

---

## 11. METERING & VISUALIZATION

### 11.1 Level Meters (Channel Strips)

| Feature | Opis |
|---------|------|
| **Peak** | Highest level indicator |
| **Peak Hold** | Sticky peak display |
| **Pre/Post Fader** | Metering point selection |
| **Clipping** | Red indicator at 0 dB |

### 11.2 MultiMeter Plugin

| Section | Opis |
|---------|------|
| **Analyzer** | 31-band FFT (1/3 octave) |
| **Goniometer** | Phase/stereo visualization |
| **Level Meter** | Peak, RMS, True Peak |
| **Loudness Meter** | LUFS (AES 128) |
| **Correlation Meter** | Phase relationship |

#### Level Display Modes
| Mode | Opis |
|------|------|
| **Peak** | Instantaneous peaks |
| **RMS** | Average level (perceived loudness) |
| **Peak & RMS** | Combined display |
| **True Peak** | Interpolated sample peaks |
| **True Peak & RMS** | Combined |

#### Loudness Meters
| Indicator | Opis |
|-----------|------|
| **LU-I** | Integrated (program average) |
| **LU-S** | Short-term (3 sec window) |
| **LU-M** | Momentary |
| **Target** | -30 to 0 LUFS |

#### Correlation Meter
| Value | Meaning |
|-------|---------|
| **+1** | Mono compatible (in-phase) |
| **0** | Uncorrelated (stereo width) |
| **-1** | Out of phase (problematic) |

### 11.3 Loudness Meter Plugin (Standalone)

| Feature | Opis |
|---------|------|
| **Standard** | AES 128 / ITU-R BS.1770 |
| **M/S/I** | Momentary, Short-term, Integrated |
| **Target Line** | Adjustable threshold |
| **Yellow Warning** | Exceeds target |
| **True Peak** | ISP display |

### 11.4 BPM Counter Plugin

| Feature | Opis |
|---------|------|
| **Detection** | Real-time tempo analysis |
| **Display** | BPM readout |
| **LED** | Beat indicator |
| **Range** | Adjustable min/max |

---

## 12. UI/UX DESIGN

### 12.1 Main Window Areas

| Area | Opis |
|------|------|
| **Control Bar** | Transport, LCD, mode buttons |
| **Tracks Area** | Main timeline workspace |
| **Inspector** | Track/region properties (left) |
| **Library** | Patches, presets (left tab) |
| **Browser** | Loops, files (right) |
| **Mixer** | Channel strips (bottom) |
| **Editors** | Piano Roll, etc. (bottom) |
| **Live Loops Grid** | Cell grid (center alternative) |
| **Smart Controls** | Macro controls (bottom) |
| **Quick Help** | Context help (bottom) |

### 12.2 Mixer Views

| View | Opis |
|------|------|
| **Single** | One expanded channel |
| **Tracks** | All project tracks |
| **All** | All channels including hidden |
| **Narrow** | Compact strips |
| **Wide** | Full strips with all controls |

### 12.3 Screensets

| Feature | Opis |
|---------|------|
| **Number** | Up to 90 |
| **Access** | Number keys 1-9, or Screenset menu |
| **Save** | Automatic on switch |
| **Lock** | Prevent changes |
| **Purpose** | Different workflow layouts |

**Common Screensets:**
1. Arrangement view
2. Mixer view
3. Editor view
4. Score view
5. Live Loops
6. etc.

### 12.4 Touch Bar Support (MacBook Pro)

| Feature | Opis |
|---------|------|
| **Transport** | Play, Record, Cycle |
| **Smart Controls** | Direct parameter access |
| **Keyboard** | Piano keys for input |
| **Drum Pads** | Beat input |
| **Custom** | User-configurable |

### 12.5 Logic Remote (iPad)

| Feature | Opis |
|---------|------|
| **Connection** | Wi-Fi or Bluetooth |
| **Mixer** | Full channel strip control |
| **Smart Controls** | Touch-based parameters |
| **Touch Instruments** | Piano, Guitar, Drums |
| **Live Loops** | Cell triggering |
| **Step Sequencer** | Pattern programming |
| **Transport** | Full transport control |
| **Plug-in View** | Parameter editing |
| **Key Commands** | Custom button layouts |

---

## 13. AI/ML FEATURES

### 13.1 Session Players

#### Drummer
| Feature | Opis |
|---------|------|
| **Genres** | Rock, Alternative, Songwriter, R&B, Electronic, Hip Hop, Percussion |
| **AI Behavior** | Follows other tracks |
| **XY Control** | Loudness × Complexity |
| **Fill Variation** | Adjustable |
| **Swing** | Per-pattern |
| **Convert to MIDI** | Full editing access |

#### Bass Player (Logic Pro 11)
| Feature | Opis |
|---------|------|
| **Players** | 8 different styles |
| **AI Training** | Pro bass players collaboration |
| **Controls** | Complexity, Intensity |
| **Techniques** | Slides, Mutes, Dead Notes, Pickup Hits |
| **Chord Following** | Global chord track |
| **Instrument** | Studio Bass plugin |

#### Keyboard Player (Logic Pro 11)
| Feature | Opis |
|---------|------|
| **Styles** | Multiple genres |
| **Voicing** | Simple blocks to extended harmony |
| **Nuances** | Key noise, pedal, resonance |
| **Chord Following** | Global chord track |
| **Instrument** | Studio Piano plugin |

#### Synth Player (Logic Pro 11.2)
| Feature | Opis |
|---------|------|
| **Capability** | Chords and bass parts |
| **Integration** | Part of Session Players |

### 13.2 Stem Splitter

| Feature | Opis |
|---------|------|
| **AI Model** | Apple Neural Engine |
| **System Requirements** | M1+ Apple Silicon |
| **Original Stems (11.0)** | 4: Vocals, Drums, Bass, Other |
| **Updated Stems (11.2)** | 6: + Guitar, Piano |
| **Quality** | Among best in class |
| **Presets** | Various stem combinations |
| **Limitation** | No manual refinement |

### 13.3 Mastering Assistant

| Feature | Opis |
|---------|------|
| **AI Analysis** | Full project scan |
| **Processing** | EQ, Dynamics, Limiting |
| **Target Loudness** | -14 LUFS (streaming default) |
| **Bypass** | A/B comparison |
| **Loudness Compensation** | Level-matched comparison |

#### Character Modes (Apple Silicon Only)
| Mode | Character |
|------|-----------|
| **Clean** | Minimal coloration, punchy |
| **Valve** | Saturated, warm |
| **Punch** | Enhanced midrange |
| **Transparent** | Modern, tight compression |

**Intel Mac:** Clean mode only

### 13.4 Smart Tempo

| AI Feature | Opis |
|------------|------|
| **Beat Detection** | Musical tempo analysis |
| **Downbeat Detection** | Bar/beat markers |
| **Time Signature** | With user hints |
| **Adaptation** | Project follows performance |

---

## 14. UNIQUE LOGIC PRO FEATURES

### 14.1 Što Logic Čini Jedinstvenim

| Feature | Konkurencija |
|---------|--------------|
| **Session Players** | Jedinstven AI band sistem |
| **Stem Splitter** | Integrisan u DAW |
| **Live Loops + Tracks** | Hibridni workflow |
| **Mastering Assistant** | AI mastering u DAW-u |
| **Sound Library** | 60-80GB uključeno |
| **Price** | $199 jednokratno |
| **Apple Ecosystem** | iPad integration |
| **Quantec Room Simulator** | Exclusive authentic recreation |

### 14.2 Sound Library

| Content | Opis |
|---------|------|
| **Total Size** | 60-80+ GB |
| **Apple Loops** | Royalty-free |
| **Alchemy Sounds** | 3000+ presets |
| **Drum Kits** | Drummer + Sampler |
| **Instruments** | Piano, Strings, Synths |
| **Producer Packs** | Oak Felder, Boys Noize, etc. |
| **Location** | Relocatable to external drive |

### 14.3 Logic Pro za iPad

| Feature | Opis |
|---------|------|
| **Compatibility** | Full project compatibility |
| **Touch Interface** | Native touch controls |
| **Session Players** | Available |
| **Stem Splitter** | M1+ iPad |
| **Price** | $4.99/month or $49/year |

---

## 15. KEYBOARD SHORTCUTS (Essential)

| Shortcut | Action |
|----------|--------|
| **Space** | Play/Stop |
| **R** | Record |
| **C** | Cycle on/off |
| **/** | Rewind to start |
| **Cmd+Z** | Undo |
| **Cmd+S** | Save |
| **A** | Toggle Automation |
| **X** | Toggle Mixer |
| **E** | Toggle Editor |
| **B** | Toggle Smart Controls |
| **P** | Toggle Piano Roll |
| **Cmd+K** | Toggle Musical Typing |
| **F** | Toggle Full Screen |
| **1-9** | Screensets |

---

## REFERENCE LINKS

### Apple Official
- [Logic Pro Mac Support](https://support.apple.com/guide/logicpro/welcome/mac)
- [Logic Pro Release Notes](https://support.apple.com/en-us/109503)

### Key Articles
- [Sound On Sound - Logic Pro Techniques](https://www.soundonsound.com/techniques)
- [Logic Pro Help](https://www.logicprohelp.com)
- [Music Tech - Logic Tutorials](https://musictech.com/tutorials/logic-pro/)

---

## ZAKLJUČAK

Logic Pro predstavlja jedan od najkompletnijih DAW paketa na tržištu, posebno za macOS korisnike. Sa integracijom AI funkcija (Session Players, Stem Splitter, Mastering Assistant), ogromnom bibliotekom zvukova (60-80GB), i jedinstvenim hibridom Live Loops + Tracks workflow-a, Logic Pro nudi profesionalni kvalitet za relativno nisku cenu od $199 jednokratno.

Za FluxForge Studio, Logic Pro služi kao referentna tačka za:
- **UI/UX design** — Screensets, Smart Controls, Touch Bar
- **Mixer architecture** — 15 inserts, 8 sends, VCA groups
- **AI features** — Session Players koncept
- **Spatial Audio** — Dolby Atmos workflow
- **Plugin hosting** — AU integration, PDC, ARA2

---

*Dokument kreiran: Januar 2026*
*Verzija Logic Pro: 11.x*
