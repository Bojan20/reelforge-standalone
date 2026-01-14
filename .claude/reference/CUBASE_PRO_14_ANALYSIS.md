# Cubase Pro 14 — Kompletna Tehnicka Analiza

**Verzija:** 14.0 (novembar 2024)
**Proizvodjac:** Steinberg (Yamaha)
**Tip:** Profesionalni DAW

---

## 1. AUDIO ENGINE ARHITEKTURA

### 1.1 Sample Rates

| Sample Rate | Podrska | Napomena |
|-------------|---------|----------|
| 44.1 kHz | Da | CD standard |
| 48 kHz | Da | Video/broadcast standard |
| 88.2 kHz | Da | 2x CD |
| 96 kHz | Da | HD Audio |
| 176.4 kHz | Da | 4x CD |
| 192 kHz | Da | Studio master |
| 384 kHz | Nuendo only | Ultra-HD (Nuendo ekskluzivno) |

**Napomena:** Cubase Pro podrzava do 192 kHz, dok Nuendo ide do 384 kHz.

### 1.2 Bit Depth (Preciznost)

| Format | Podrska | Namena |
|--------|---------|--------|
| 16-bit integer | Da | CD export |
| 24-bit integer | Da | Profesionalni standard |
| 32-bit integer | Da | High-precision recording |
| 32-bit float | Da | Interno procesiranje |
| 64-bit float | Da | Maximum precision processing |

**Processing Precision:**
- Cubase 14 koristi 64-bit float interno procesiranje
- Svi projektni fajlovi u Cubase 14 koriste 64-bit format
- Mozete birati izmedju 32-bit float i 64-bit float u Studio Setup

### 1.3 Buffer Sizes

| Buffer Size | Latencija @ 48kHz | Namena |
|-------------|-------------------|--------|
| 32 samples | 0.67 ms | Ultra-low latency tracking |
| 64 samples | 1.33 ms | Low latency tracking |
| 128 samples | 2.67 ms | Tracking sa efektima |
| 256 samples | 5.33 ms | Balans tracking/mixing |
| 512 samples | 10.67 ms | Mixing |
| 1024 samples | 21.33 ms | Heavy mixing |
| 2048 samples | 42.67 ms | Offline processing |
| 4096 samples | 85.33 ms | Maximum stability |

### 1.4 ASIO-Guard Tehnologija

**Koncept:**
ASIO-Guard je Steinberg-ova proprietary tehnologija za optimizaciju CPU performansi. Deli audio procesiranje na dva puta:

1. **Real-time Path:**
   - Tracks sa aktivnim monitoringom
   - Record-enabled tracks
   - VSTi sa aktivnim MIDI inputom
   - Mora zavrsiti kalkulacije unutar buffer ciklusa

2. **Prefetch/ASIO-Guard Path:**
   - Tracks bez live input-a
   - Koristi veci interni buffer
   - Pre-kalkulise audio podatke unapred
   - Skladisti u prefetch queue

**ASIO-Guard Levels:**

| Level | Buffer Multiplier | Latency Impact | Best For |
|-------|-------------------|----------------|----------|
| Low | 2x | Minimal | Live tracking |
| Normal | 4x | Moderate | Balanced workflow |
| High | 8x | Significant | Heavy mixing |

**Dinamicko Prebacivanje:**
- Kada aktivirate monitoring na track-u, Cubase ga INSTANT prebacuje iz ASIO-Guard u real-time path
- Ista logika za VSTi kada su record-enabled

**Prednosti:**
- Manje dropout-a
- Mogucnost koriscenja vise track-ova i plug-in-a
- Mogucnost koriscenja manjih buffer size-ova

### 1.5 Multi-threading Model

**Audio Performance Monitor (Cubase 14 novo):**
- Novi algoritam za odvojeno merenje real-time i prefetch thread load-a
- Dropout sekcija — granularna analiza do specificnih track-ova
- Ugradjen countermeasures za detektovane overload-e

**Thread Distribution:**
- Audio engine koristi sve dostupne CPU core-ove
- Hyperthreading podrska (moze se iskljuciti u BIOS-u za stabilnost)
- Simetricna distribucija load-a preko core-ova

### 1.6 Audio Driver Support

| Driver Type | Platforma | Latency | Napomena |
|-------------|-----------|---------|----------|
| ASIO | Windows | Ultra-low | Preporuceno za Windows |
| ASIO4ALL | Windows | Low-medium | Generic ASIO driver |
| CoreAudio | macOS | Low | Native macOS |
| WASAPI | Windows | Medium | Windows native |
| WDM | Windows | High | Legacy |
| JACK | Linux | Low | Pro audio Linux |
| PipeWire | Linux | Low | Modern Linux |

### 1.7 Plugin Delay Compensation (PDC)

**Implementacija:**
- Automatska kompenzacija kroz ceo audio path
- Svi audio kanali ostaju sinhronizovani
- VST3 plug-in-i prijavljuju svoju latenciju host-u
- Host (Cubase) kompenzuje delayujuci ostale track-ove

**Constrain Delay Compensation:**
- Funkcija za minimizaciju latencije tokom snimanja
- Privremeno deaktivira high-latency plug-in-e
- Odrzava zvuk mixa koliko je moguce

**Technical Note:**
- Cubase/Nuendo imaju reputaciju najboljeg PDC sistema u industriji
- Kompenzacija radi samo za recorded tracks (ne za live input)
- Neki plug-in-i ne prijavljuju tacnu latenciju

---

## 2. DSP PROCESORI (STOCK PLUGINS)

### 2.1 EQ Plugins

#### 2.1.1 Frequency 2 (Flagship EQ)

**Osnovne Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj bendova | 8 (potpuno parametarski) |
| Filter tipovi | Low Shelf, Peak, High Shelf, Notch, Cut |
| Cut filter slopes | 6, 12, 24, 48, 96 dB/oct |
| M/S Processing | Da (per-band) |
| L/R Processing | Da (per-band) |
| Dynamic EQ | Da (per-band) |
| Linear Phase | Da (per-band) |
| Sidechain Inputs | 8 (jedan po bendu) |

**Filter Tipovi po Bendu:**
- **Band 1 & 8:** Cut (6/12/24/48/96), Low/High Shelf, Peak, Notch
- **Band 2-7:** Low Shelf, Peak, High Shelf, Notch

**Dynamic EQ Sekcija:**
- Threshold control
- Ratio control
- Attack time
- Release time
- Auto mode
- Per-band on/off

**Linear Phase Mode:**
- Izbegava frekvencijski-zavisne fazne pomeraje
- Povecava latenciju
- Moze izazvati pre-ringing na niskim frekvencijama sa strmim slope-ovima
- Deaktivira dynamic filtering za taj bend

**Sidechain Per-Band:**
- Svaki bend ima sopstveni sidechain input
- Omogucava frekvencijski-specificno ducking
- Masking detection funkcija

**Display Modes:**
- Multi-band view
- Single band (Sing) mode za detaljnu kontrolu

#### 2.1.2 StudioEQ

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj bendova | 4 |
| Filter tipovi | 2x Shelf, 2x Peak |
| Gain range | ±24 dB |
| Q range | 0.1 - 10 |

**Karakteristike:**
- Clean, transparent zvuk
- Nizi CPU footprint od Frequency 2
- Dobar za subtilne korekcije

#### 2.1.3 Channel EQ (Channel Strip)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj bendova | 5 (4 parametarska + 1 filter) |
| Low Cut | 20 Hz - 500 Hz |
| Slopes | 6, 12, 24, 48 dB/oct |
| Gain range | ±24 dB |

**Modeli:**
- Hardware-inspired EQ modeli
- Mozete birati razlicite karakteristike

#### 2.1.4 GEQ-10 / GEQ-30

**Specifikacije:**

| Parametar | GEQ-10 | GEQ-30 |
|-----------|--------|--------|
| Broj bendova | 10 | 30 |
| Gain range | ±12 dB | ±12 dB |
| Band spacing | 1 octave | 1/3 octave |

**EQ Modes:**
1. Serial filters (accurate response)
2. Classic parallel (colored response)
3. Parallel sa gain-dependent resonance
4. Parallel sa inverted resonance
5. Parallel sa sample-rate dependent resonance

**Kontrole:**
- Output gain
- Flatten (reset)
- Range (scale curve)
- Invert (flip curve)

### 2.2 Dynamics Plugins

#### 2.2.1 Compressor

**Specifikacije:**

| Parametar | Range/Options |
|-----------|---------------|
| Threshold | -60 to 0 dB |
| Ratio | 1:1 to 8:1 |
| Attack | 0.1 to 100 ms |
| Release | 10 to 1000 ms + Auto |
| Knee | Soft / Hard |
| Detection | Peak / RMS / Mix (0-100) |
| Make-up Gain | 0 to 24 dB |
| Sidechain | Da |

**Karakteristike:**
- Graphical display compressor curve
- Gain Reduction meter
- Auto Release mode (program-dependent)
- Peak/RMS blend slider (0 = Pure Peak, 100 = Pure RMS)

#### 2.2.2 Tube Compressor

**Specifikacije:**
- Emulacija LA-2A stila
- Tube saturation amount control
- Fixed compression ratio
- Limiter option
- Dry/Wet mix
- Sidechain support
- Attack i Release kontrole (za razliku od originala)

#### 2.2.3 Vintage Compressor

**Specifikacije:**
- Modelovan po vintage VCA kompresorima
- Classic sound character
- Program-dependent response

#### 2.2.4 MultibandCompressor

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj bendova | 4 (ili 5) |
| Crossover tipovi | Adjustable |
| Per-band controls | Threshold, Ratio, Attack, Release, Gain |
| Look-ahead | Da (moze se iskljuciti za Live mode) |
| Solo per band | Da |
| Sidechain | Da (global + per-band) |
| Auto make-up gain | Da |

**Live Mode:**
- Deaktivira look-ahead
- Zero latency
- Bolje za live procesiranje

#### 2.2.5 Limiter

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Input Gain | -24 to +24 dB |
| Output Ceiling | -24 to 0 dB |
| Release | 0.1 to 1000 ms + Auto |

#### 2.2.6 Brickwall Limiter

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Latencija | 1 ms (fiksna) |
| Ceiling | Adjustable |
| Release | Adjustable |
| Oversampling | Da (opciono) |
| Metering | Input, Output, Limiting amount |

**Namena:**
- Poslednji u signal chain (pre dithering-a)
- Redukcija okazionalnih peak-ova
- Oversampling detektuje inter-sample peak-ove

#### 2.2.7 Maximizer

**Specifikacije:**
- Lookahead limiting
- Soft clipping option
- Output ceiling
- Optimize (mix between soft clip and limiting)

#### 2.2.8 Gate

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Threshold | -80 to 0 dB |
| Range | -80 to 0 dB |
| Attack | 0.1 to 100 ms |
| Hold | 0 to 2000 ms |
| Release | 10 to 1000 ms |
| Side-chain filter | Da (AF button) |
| Listen function | Da (LST) |

#### 2.2.9 Expander

**Specifikacije:**
- Ratio control (soft expansion)
- Threshold
- Attack, Release
- Range

#### 2.2.10 VSTDynamics

**Kombinovani procesor:**
- Gate modul
- Compressor modul
- Limiter modul
- Sve u jednom plug-in-u

### 2.3 Reverb Plugins

#### 2.3.1 REVerence (Convolution Reverb)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Tip | Convolution |
| Stereo/Surround | Da (oba) |
| Program Matrix | 36 programa |
| IR Import | Da |
| IR Formats | WAV, AIFF |

**Karakteristike:**
- Procesira audio prema impulse response-u
- Rekreira karakteristike stvarnih prostora
- Moze koristiti IR-ove od:
  - Pravih akusticnih prostora
  - Hardware reverb-a (plate, spring, digital)
  - Custom IR-ova (starter pistol, balloon, white noise burst)

**Kontrole:**
- Pre-delay
- Size
- ER/Tail balance
- Reverse
- EQ
- Damping

#### 2.3.2 RoomWorks (Algorithmic Reverb)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Tip | Algorithmic |
| Stereo/Surround | Da (oba) |
| Efficiency | 10-50 (CPU management) |

**Karakteristike:**
- Digitalna generacija reverb-a
- Mnogo repetitions input signala
- Skulptiranje za prirodan ton i decay
- Cist zvuk
- Detaljna kontrola generatora

**Kontrole:**
- Room size
- Diffusion
- Pre-delay
- Decay time
- Damping (High, Low)
- Mix

#### 2.3.3 RoomWorks SE

**Specifikacije:**
- Lighter verzija RoomWorks-a
- Manji CPU footprint
- Osnovne kontrole

#### 2.3.4 REVelation

**Specifikacije:**
- Algorithmic reverb
- Vise karakter-orijentisan od RoomWorks-a
- Modulation opcije

#### 2.3.5 Shimmer (Cubase 14 novo)

**Specifikacije:**
- Reverb sa pitch-shifting-om
- Inspirisan Eventide efektima
- Ethereal, spacious zvukovi
- Resizable interface

### 2.4 Delay Plugins

#### 2.4.1 Studio Delay (Cubase 14 novo)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Delay Patterns | 8 |
| Modulation | Da |
| Distortion | Da |
| Reverb | Da |
| Pitch | Da |
| Tape Aging | Da |
| Resizable UI | Da |

**Karakteristike:**
- Svestran delay/echo efekt
- Pattern-based delays
- Integrated saturation

#### 2.4.2 StereoDelay

**Specifikacije:**
- Nezavisni L/R delay times
- Feedback
- Cross-feedback (ping-pong)
- Tempo sync
- Filter

#### 2.4.3 MonoDelay

**Specifikacije:**
- Single delay line
- Feedback
- Tempo sync
- Filter

#### 2.4.4 PingPongDelay

**Specifikacije:**
- Stereo bouncing effect
- Spatial control
- Tempo sync

### 2.5 Modulation Plugins

#### 2.5.1 Chorus

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Delay | Adjustable |
| Frequency | Adjustable |
| Waveforms | Triangle, Ramp, Pulse |
| Stages | 1-4 delay taps |
| Tempo Sync | Da |

#### 2.5.2 Flanger

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Delay | 0-100 ms |
| Feedback | Adjustable |
| Shape Sync | Triangle/Ramp variants |
| Stereo Basis | Da |
| Tempo Sync | Da |

#### 2.5.3 Phaser

**Specifikacije:**
- All-pass filter stages
- Feedback
- Depth
- Rate/Tempo sync

#### 2.5.4 Rotary

**Specifikacije:**
- Leslie speaker emulation
- Slow/Fast speed
- Horn/Drum simulation

#### 2.5.5 Vibrato

**Specifikacije:**
- Pitch modulation
- Rate
- Depth

#### 2.5.6 Tremolo

**Specifikacije:**
- Amplitude modulation
- Rate
- Depth

### 2.6 Saturation/Distortion Plugins

#### 2.6.1 Magneto II

**Specifikacije:**
- Analog tape saturation emulation
- Tape compression karakteristike
- Must-have Cubase plug-in

**Kontrole:**
- Drive
- Low/High frequency saturation
- HF Adjust
- Tape speed simulation

#### 2.6.2 Quadrafuzz V2

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj bendova | 4 |
| Saturation Types | Tape, Tube, Distortion, Amp, Decimator |
| Per-band Delay | Da |
| Per-band Pan | Da |
| Per-band Mix | Da |
| Per-band Gate | Da |
| True Stereo | Da |

**Izuzetno koristan za:**
- Multiband distortion
- Lo-fi effects
- Parallel saturation

#### 2.6.3 Distortion

**Specifikacije:**
- Basic distortion
- Drive
- Tone
- Mix

#### 2.6.4 SoftClipper

**Specifikacije:**
- Soft saturation
- Smooth clipping curve
- Subtle warmth

#### 2.6.5 BitCrusher

**Specifikacije:**
- Sample rate reduction
- Bit depth reduction
- Lo-fi/retro effects

#### 2.6.6 Grungelizer

**Specifikacije:**
- Vinyl noise
- Crackle
- Distortion

### 2.7 Filter Plugins

#### 2.7.1 Auto Filter (Cubase 14 novo)

**Specifikacije:**
- Envelope following filter modulation
- High-pass, Low-pass, Band-pass
- Pulsating filter effects
- Resizable interface

#### 2.7.2 Dual Filter

**Specifikacije:**
- Two filters in series/parallel
- HP/LP/BP combinations
- Resonance

#### 2.7.3 WahWah

**Specifikacije:**
- Classic wah effect
- Pedal position
- Auto-wah option

### 2.8 Utility Plugins

#### 2.8.1 Volume (Cubase 14 novo)

**Specifikacije:**
- Multi-channel gain adjustment
- Simple gain tool
- Resizable interface

#### 2.8.2 Underwater (Cubase 14 novo)

**Specifikacije:**
- One-knob low-pass filter
- "Muffled" sound effect
- Simple UI

#### 2.8.3 MixConvert V6

**Specifikacije:**
- Channel format conversion
- Surround to stereo downmix
- Configurable routing

#### 2.8.4 MonoToStereo

**Specifikacije:**
- Width control
- Delay-based stereo expansion

#### 2.8.5 StereoEnhancer

**Specifikacije:**
- Stereo width control
- M/S balance
- Color control

---

## 3. MIXER ARHITEKTURA

### 3.1 Channel Strip Signal Flow

```
[Input] → [Pre Section] → [Inserts 1-6] → [Strip] → [EQ] →
[Fader] → [Inserts 7-8] → [Sends] → [Panner] → [Direct Routing] → [Output]
```

**Detaljan Signal Flow:**

1. **Input Stage**
   - Input gain/trim
   - Phase invert
   - Input routing selection

2. **Pre Section**
   - Pre-fader processing
   - Input filtering

3. **Insert Section (Pre-Fader)**
   - Slots 1-6: Pre-fader inserts
   - Signal flows top-to-bottom
   - Svaki slot moze hostovati VST2/VST3 plug-in

4. **Channel Strip**
   - Moze se pozicionirati pre ili posle inserts
   - Redosled modula je podesiv

5. **Fader**
   - Volume control
   - Automation point

6. **Insert Section (Post-Fader)**
   - Slots 7-8: Post-fader inserts
   - Za limitere, saturation, itd.

7. **Sends**
   - Pre ili post-fader (per-send)
   - Level per send
   - Pan per send

8. **Panner**
   - Stereo panner (standard)
   - Surround panner (za surround tracks)
   - VST MultiPanner (za Atmos)

9. **Direct Routing**
   - 7 routing destinations
   - Post-fader, post-panner

10. **Output**
    - Routing to groups, outputs, etc.

### 3.2 Channel Strip Modules

**Dostupni Moduli:**

| Modul | Funkcija | Varijante |
|-------|----------|-----------|
| Gate | Noise gate | Standard Gate |
| Comp | Compressor | Standard, Tube, Vintage |
| Tools | Utility | DeEsser, EnvelopeShaper |
| Sat | Saturation | Magneto II, Tape, Tube |
| Limit | Limiter | Standard, Maximizer, Brickwall |
| EQ | Equalizer | 4-band parametric |

**Redosled:**
- Moduli se mogu reorganizovati drag-and-drop
- Default: Gate → Comp → Tools → Sat → Limit → EQ
- Moze se prilagoditi workflow-u

### 3.3 Insert Architecture

| Insert Slot | Position | Typical Use |
|-------------|----------|-------------|
| 1-6 | Pre-fader | EQ, Compression, Effects |
| 7-8 | Post-fader | Limiting, Final saturation |

**Flexibility:**
- Channel Strip moze biti pre ili post inserts
- Moze se menjati preko Strip tab opcija

### 3.4 Send Architecture

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Broj Send-ova | 8 po kanalu |
| Pre/Post Fader | Per-send selectable |
| Level | Per-send |
| Pan | Per-send |
| Destination | FX Channels, Groups, Outputs |

**Pre-Fader Sends:**
- Signal pre fader-a
- Nije afektovan fader podesavanjima
- Idealno za monitor/cue mixeve

**Post-Fader Sends:**
- Signal posle fader-a
- Prati fader promene
- Idealno za FX sends (reverb, delay)

### 3.5 Bus Routing

#### 3.5.1 Group Channels

**Karakteristike:**
- Audio summing bus
- Full channel strip
- Insert slots
- Sends
- Mogu se nested-ovati

**Kreiranje:**
- Add Track > Group Channel
- Stereo ili Surround konfiguracija

#### 3.5.2 FX Channels

**Karakteristike:**
- Dedicated za send effects
- Full channel strip
- Insert slots
- Output routing

**Kreiranje:**
- Add Track > FX Channel
- Automatski se kreira send routing

#### 3.5.3 VCA Faders (Cubase Pro Only)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Kontrolise | Volume, Mute, Solo, Listen, Monitor, Record |
| Audio Routing | Nema (kontroler samo) |
| Automation | Da (kombinuje se sa linked channels) |
| Nesting | Da (VCA kontrolise VCA) |

**Kako radi:**
- Povezuje se sa Link Group
- Dodaje/oduzima dB vrednost od linked channels
- Relativna kontrola (cuva balance)

**Primer:**
- Channel A na -6 dB
- VCA na 0 dB
- Pomerite VCA na +3 dB
- Channel A je sada -3 dB (-6 + 3)

**Automation:**
- VCA automation se kombinuje sa channel automation
- Moze se "bake" kombinovana automation
- Non-destructive dok se ne kombinuje

### 3.6 Direct Routing (Cubase Pro Only)

**Specifikacije:**

| Parametar | Vrednost |
|-----------|----------|
| Routing Destinations | 7 |
| Signal Position | Post-fader, Post-panner |
| Applicable To | Audio, Instrument, FX, Groups, Outputs |
| Automation | Da |

**Namena:**
- Kreiranje alternativnih mix verzija
- Simultano slanje na vise destinacija
- Brzo prebacivanje izmedju output-a

**Summing Modes:**
- Exclusive (jedan po jedan)
- Summing (vise simultano)

**Automatic Downmixing:**
- Surround → Stereo automatski

### 3.7 Sidechain Routing

**Implementacija:**
- VST3 plug-in-i eksponiraju sidechain inputs
- Routing iz bilo kog audio source-a
- Pre/Post fader opcije za sidechain signal
- Multiple sidechain inputs (npr. Frequency 2 ima 8)

**Workflow:**
1. Aktivirajte Sidechain na plug-in-u (SC button)
2. Odaberite source iz dropdown-a
3. Ili kreirajte Send sa sidechain destination

### 3.8 Surround/Dolby Atmos Support

**Podrzani Formati:**

| Format | Channels | Availability |
|--------|----------|--------------|
| Stereo | 2.0 | Sve verzije |
| LRC | 3.0 | Pro |
| Quadro | 4.0 | Pro |
| 5.0 | 5.0 | Pro |
| 5.1 | 5.1 | Pro |
| 6.0 | 6.0 | Pro |
| 6.1 | 6.1 | Pro |
| 7.0 | 7.0 | Pro |
| 7.1 | 7.1 | Pro |
| 7.1.4 | 7.1.4 | Pro (Atmos) |
| 22.2 | 22.2 | Nuendo only |

**Dolby Atmos u Cubase Pro 14:**

| Feature | Cubase Pro 14 | Nuendo |
|---------|---------------|--------|
| Max Layout | 7.1.4 | 22.2+ |
| Beds | 1 | Multiple |
| Objects | Da | Da |
| ADM Export | Da | Da |
| ADM Import | Ne | Da |
| External Renderer | Ne | Da |
| Internal Renderer | Da | Da |
| Binaural Downmix | Da | Da |

**VST MultiPanner:**
- Bed mode
- Object mode
- 3D positioning
- Automation support

**Setup Assistant:**
- Automated Atmos project setup
- Bed/Object configuration
- Renderer routing

---

## 4. TIMELINE / ARRANGEMENT

### 4.1 Track Types

| Track Type | Funkcija | Audio/MIDI |
|------------|----------|------------|
| Audio Track | Audio recording/playback | Audio |
| Instrument Track | VSTi hosting | MIDI → Audio |
| MIDI Track | MIDI playback | MIDI |
| Sampler Track | Sample playback | MIDI → Audio |
| Drum Track (v14 novo) | Drum Machine | MIDI → Audio |
| Group Channel | Audio summing | Audio |
| FX Channel | Send effects | Audio |
| VCA Fader | Group control | Control |
| Folder Track | Organization | N/A |
| Chord Track | Chord events | Control |
| Tempo Track | Tempo automation | Control |
| Signature Track | Time signature | Control |
| Transpose Track | Global transpose | Control |
| Arranger Track | Section arrangement | Control |
| Marker Track | Navigation markers | Control |
| Ruler Track | Additional time ruler | Display |
| Video Track | Video playback | Video |

### 4.2 Clip/Event Types

**Audio Events:**
- Reference audio clips
- Non-destructive
- Mogu se slice-ovati, fade-ovati, warp-ovati

**Audio Clips:**
- Actual audio data reference
- Stored in Pool
- Multiple events mogu referencirati isti clip

**MIDI Parts:**
- Container za MIDI events
- Mogu se editovati u MIDI editors
- Copy/reference relationship

**Pattern Events (v14 novo):**
- Step sequencer patterns
- Convert to MIDI Part moguce

**Automation Events:**
- Parameter automation data
- Continuous ili stepped

### 4.3 Fade/Crossfade Types

**Fade Types:**

| Tip | Oblik | Namena |
|-----|-------|--------|
| Linear | Straight line | Basic fade |
| Exponential | Curve out | Slow start, fast end |
| Logarithmic | Curve in | Fast start, slow end |
| S-Curve | Smooth transition | Natural sounding |
| Cosine | Smooth | Equal power feel |

**Crossfade Types:**
- Symmetric (jednaki fade out/in)
- Asymmetric (razliciti oblik za in/out)
- Equal Power (compensated)
- Equal Gain (linear)

**Crossfade Editor:**
- Visual curve editing
- Pre-listen
- Length adjustment
- Curve type selection

### 4.4 Automation

**Automation Modes:**

| Mode | Funkcija |
|------|----------|
| Read | Playback automation |
| Write | Overwrite sve |
| Touch | Write dok se drzi, return to previous |
| Latch | Write od prvog touch-a do stop |
| Trim | Relative adjustment |

**Automation Features:**
- Per-track automation lanes
- Multiple parameters per track
- Virgin territory (gaps)
- Automation follows edit
- Automation panel za batch operations

**Supported Parameters:**
- Prakticki svi plug-in parametri
- Volume, Pan, Mute, Solo
- Send levels
- Insert bypass
- EQ parameters
- VCA values

### 4.5 Quantize / Grid

**Grid Values:**

| Value | Note |
|-------|------|
| 1/1 | Whole note |
| 1/2 | Half note |
| 1/4 | Quarter note |
| 1/8 | Eighth note |
| 1/16 | Sixteenth note |
| 1/32 | Thirty-second note |
| 1/64 | Sixty-fourth note |
| Triplet | All above as triplets |
| Dotted | All above as dotted |

**Quantize Panel:**

| Feature | Funkcija |
|---------|----------|
| Grid Quantize | Snap to grid |
| Iterative Quantize | Partial move toward grid |
| Swing | Add swing feel |
| Groove Quantize | Apply groove from other material |
| AudioWarp Quantize | Time-stretch audio to grid |
| Slice Quantize | Slice audio at hitpoints |

### 4.6 Markers

**Marker Types:**

| Tip | Funkcija |
|-----|----------|
| Position Marker | Single point |
| Cycle Marker | Range (start/end) |
| Arranger Event | Section for arrangement |

**Features:**
- Color coding
- Naming
- Track-based ili global markers
- Export marker data

### 4.7 Tempo Track

**Features:**
- Tempo automation
- Linear ili ramp changes
- Tempo detection from audio
- Import tempo from MIDI
- Time warp tool
- Musical mode (follows tempo)

**Tempo Detection:**
- Analyze audio za tempo
- Kreiranje tempo track from detection
- Manual adjustment

### 4.8 Chord Track

**Features:**
- Chord event timeline
- Voicing options
- Scale assistant
- Chord Pads (za real-time input)
- VariAudio chord following
- MIDI transformation based on chords

**Chord Assistant:**
- Chord suggestions
- Circle of fifths
- Proximity mode
- Common tones mode

### 4.9 Arranger Track

**Features:**
- Define arranger sections (events)
- Create arrangement chains
- Play sections u bilo kom redosledu
- Repeats per section
- Flatten arrangement (render to linear)

**Workflow:**
- Non-linear songwriting
- Live performance (section triggering)
- Multiple arrangement versions

---

## 5. EDITING CAPABILITIES

### 5.1 VariAudio (Cubase Pro Only)

**Funkcija:** Pitch i timing editing za monophonic audio

**Specifikacije:**

| Feature | Opis |
|---------|------|
| Pitch Segments | Automatic note detection |
| Pitch Editing | Drag to change pitch |
| Timing Editing | Warp Start/End controls |
| Pitch Quantize | Snap to scale/chromatic |
| Pitch Straightening | Reduce pitch variation |
| Vibrato Editing | Amount, Rate |
| Formant Shift | Preserve natural tone |

**VariAudio 3 Smart Controls:**

| Control | Funkcija |
|---------|----------|
| Tilt | Pitch tilt iznad note |
| Warp Start | Time-stretch start |
| Warp End | Time-stretch end |
| Straighten Pitch | Reduce wobble |
| Set Range Start | Define straighten range |
| Set Range End | Define straighten range |
| Vibrato | Add/edit vibrato |
| Formant | Shift formants |

**Scale Assistant:**
- Constrain to scale
- Multiple scale types
- Root note selection
- Visual pitch grid

### 5.2 AudioWarp

**Features:**

| Feature | Funkcija |
|---------|----------|
| Free Warp | Manual warp marker placement |
| Warp to Grid | Snap markers to grid |
| Musical Mode | Follow tempo changes |
| Hitpoint Warp | Warp at hitpoints |
| Multitrack Warp | Phase-coherent multi-track |

**Algorithms:**

| Algorithm | Best For | Quality | CPU |
|-----------|----------|---------|-----|
| elastique Pro | General | High | Medium |
| elastique Pro - Time | Rhythmic | High | Medium |
| elastique Pro - Pitch | Melodic | High | Medium |
| elastique Efficient | Real-time | Good | Low |
| Standard | General | Good | Low |
| Limited | Preservation | Basic | Low |

**Multitrack AudioWarp:**
- Folder group editing
- Single hitpoint detection (priority)
- Phase-coherent stretching

### 5.3 Hitpoints

**Features:**

| Feature | Funkcija |
|---------|----------|
| Auto Detection | Threshold-based |
| Manual Edit | Add/remove hitpoints |
| Sensitivity | Adjustable threshold |
| Create Slices | Cut at hitpoints |
| Create Markers | From hitpoints |
| Create MIDI | From hitpoints |
| Create Groove | Extract groove |

**Slice Rules (Multi-track):**
- Priority per track
- Kick priority for drums
- Combined detection

### 5.4 Sample Editor

**Features:**

| Feature | Funkcija |
|---------|----------|
| Waveform Display | Zoomable |
| Selection | Range selection |
| Processing | Offline processing |
| VariAudio Tab | Pitch editing |
| Hitpoints Tab | Transient detection |
| AudioWarp Tab | Time stretching |
| Range Tab | Region definition |

**Offline Processing:**
- Gain
- Normalize
- DC Offset Removal
- Fade In/Out
- Reverse
- Time Stretch
- Pitch Shift
- Resample

### 5.5 Direct Offline Processing (DOP)

**Karakteristike:**
- Non-destructive offline effects
- Clip-based (ne track-based)
- Full undo/redo u bilo kom redosledu
- Instant preview
- Plug-in support

**Workflow:**
1. Select audio events
2. Open DOP window (Audio > Direct Offline Processing)
3. Add processes/plug-ins
4. Processes apply immediately
5. Can modify/remove anytime
6. Original audio intact

**vs Render in Place:**
- DOP: Clip-based, non-destructive to clip
- RIP: Creates new track, mutes original

### 5.6 SpectraLayers Integration

**SpectraLayers Go 11 (included):**
- Spectral editing
- Sound design
- Audio restoration
- Audio repair
- Frequency painting
- Layer separation

**ARA2 Integration:**
- Seamless transfer
- Edits reflect in Cubase
- Non-destructive workflow

---

## 6. MIDI CAPABILITIES

### 6.1 MIDI Editors

#### 6.1.1 Key Editor

**Features:**
- Piano roll view
- Velocity editing
- Controller lanes
- Multiple parts
- Chord display
- Scale assistant
- In-Place editing option

#### 6.1.2 Score Editor (Cubase 14 - Dorico Technology)

**Cubase 14 Features:**
- Rebuilt sa Dorico tehnologijom
- Modern notation rendering
- Playback integration
- Practical scoring focus
- Export to Dorico za advanced notation

**Notation Elements:**
- Notes, rests
- Clefs, key signatures
- Time signatures
- Articulations
- Dynamics
- Slurs, ties
- Lyrics
- Chord symbols

#### 6.1.3 Drum Editor

**Features:**
- Drum map integration
- Diamond/line display
- Per-pitch lanes
- Velocity editing
- Pattern-based editing
- Custom drum maps

#### 6.1.4 List Editor

**Features:**
- Event list view
- All MIDI events
- Precise value editing
- Filter by event type
- SysEx editing

#### 6.1.5 In-Place Editor

**Features:**
- Edit directly on track
- No separate window
- Quick edits

### 6.2 MIDI Effects

**Included MIDI FX:**

| Effect | Funkcija |
|--------|----------|
| Arpache 5 | Arpeggiator |
| Arpache SX | Advanced arpeggiator |
| Auto LFO | LFO controller generator |
| Beat Designer | Pattern sequencer |
| Chorder | Chord generator |
| Compressor | MIDI velocity compressor |
| Context Gate | Velocity gate |
| Density | Note density control |
| Micro Tuner | Microtonal tuning |
| MIDI Control | CC/PC generator |
| MIDI Echo | MIDI delay |
| MIDI Modifiers | Basic MIDI transform |
| MIDI Monitor | Display MIDI data |
| Note to CC | Convert notes to CC |
| Quantizer | Real-time quantize |
| StepDesigner | Pattern sequencer |
| Track Control | GS/XG control |
| Transformer | MIDI transformation |

### 6.3 Expression Maps

**Funkcija:** Map articulations to keyswitches ili CC

**Features:**
- Per-track assignment
- Articulation lanes
- Visual articulation editing
- Import/Export maps
- VST Expression compatible
- Sound Variations support

**Workflow:**
1. Create Expression Map
2. Define articulations (text, symbol)
3. Map to output (keyswitch, CC, PC)
4. Assign to track
5. Paint articulations in articulation lane
6. Automatic keyswitch/CC output

### 6.4 Note Expression (VST3)

**Funkcija:** Per-note parameter automation

**Features:**
- Per-note pitch bend
- Per-note volume
- Per-note pan
- Per-note expression
- VST3 specific parameters
- Polyphonic expression

**vs Standard Automation:**
- Standard: Affects all notes
- Note Expression: Per-note, polyphonic

**Compatible Instruments:**
- HALion Sonic
- VSL instruments
- Retrologue
- Any VST3 Note Expression compatible

### 6.5 Chord Assistant

**Features:**

| Mode | Funkcija |
|------|----------|
| Circle of Fifths | Harmonic relationships |
| Proximity | Similar chords |
| Common Notes | Shared tones |
| Complexity | Filter by complexity |

**Chord Pads:**
- 8 assignable pads
- Real-time triggering
- Voicing options
- Pattern player
- Remote control

### 6.6 Scale Assistant

**Features:**
- Lock to scale
- Visual scale overlay
- Multiple scale types
- Root note selection
- Editing constraint
- Pitch correction guide

---

## 7. PLUGIN HOSTING

### 7.1 Supported Formats

| Format | Support | Note |
|--------|---------|------|
| VST2 | Da (disabled by default v14) | Legacy, re-enable u settings |
| VST3 | Da | Preferred format |
| ARA2 | Da | Audio Random Access |

**VST2 Status u Cubase 14:**
- Disabled by default
- Re-enable: Edit > Preferences > VST > Plug-ins > Enable VST 2 Plug-ins
- Legacy support za stare plug-in-e

### 7.2 Plugin Manager

**Features:**

| Feature | Funkcija |
|---------|----------|
| Collections | Custom plug-in groups |
| Hide/Show | Per-plug-in visibility |
| Path Management | Scan paths |
| Re-scan | Refresh plug-in list |
| Info Display | Version, vendor, format |

**Organization:**
- Create collections (npr. "Drums", "Vocals", "Mastering")
- Drag plug-ins to collections
- Show only specific collections

### 7.3 Plugin Delay Compensation

**Automatic PDC:**
- Cubase automatski detektuje plug-in latency
- Kompenzuje sve tracks da budu sinhronizovani
- VST3 plug-in-i prijavljuju latenciju

**Constrain Delay Compensation:**
- Minimizuje latency tokom recording-a
- Bypasses high-latency plug-ins
- Aktivira se na toolbar-u

### 7.4 Blacklist Handling

**Features:**
- Automatic crash detection
- Blacklist failed plug-ins
- Manual blacklist management
- Re-activate blacklisted plug-ins
- Safe mode scan

### 7.5 32-bit Bridging

**Status:**
- Cubase 14 je cist 64-bit
- Nema native 32-bit bridging
- Third-party bridges (jBridge) za legacy 32-bit

---

## 8. PROJECT MANAGEMENT

### 8.1 Project Structure

**File Types:**

| Extension | Sadrzaj |
|-----------|---------|
| .cpr | Cubase Project (main file) |
| .bak | Backup project |
| Audio/ | Recorded audio files |
| Edits/ | DOP processed files |
| Images/ | Waveform images |
| Track Pictures/ | Track icons |

**Project Folder Structure:**
```
MyProject/
├── MyProject.cpr          (main project)
├── MyProject.bak          (backup)
├── Audio/                  (recorded audio)
│   ├── Track 01.wav
│   └── Track 02.wav
├── Edits/                  (DOP files)
├── Images/                 (waveform cache)
└── Track Pictures/         (custom icons)
```

### 8.2 Pool Management

**Features:**
- Audio clip database
- Usage tracking
- Missing file detection
- Conform files (copy to project)
- Remove unused media
- Prepare Archive

**Pool Window:**
- Clips view
- Folder organization
- Info display (channels, sample rate, bit depth)
- Import/Export

### 8.3 MediaBay

**Features:**

| Feature | Funkcija |
|---------|----------|
| Locations | Folder shortcuts |
| Results Browser | File listing |
| Previewer | Audio preview |
| Attributes | Metadata filtering |
| Search | Text search |
| Tags | Custom tags |

**Supported File Types:**
- Audio: WAV, AIFF, MP3, OGG, FLAC, WMA
- MIDI: .mid, .smf
- Video: Various
- Presets: VST presets, Track presets
- Loops: REX, Apple Loops

### 8.4 Track/FX Chain Presets

**Track Presets:**
- Save complete track settings
- Inserts, EQ, Sends, Routing
- Import onto new tracks
- MediaBay integration

**FX Chain Presets:**
- Save insert chain
- Load to any channel
- MediaBay storage

### 8.5 Project Templates

**Features:**
- Save complete project as template
- Include tracks, routing, plug-ins
- Custom templates u New Project dialog
- Factory templates included

### 8.6 Backup/Autosave

**Backup on Save:**
- Creates .bak file
- Configurable number of backups

**Autosave:**
- Periodic automatic save
- Configurable interval (minutes)
- Autosave folder

---

## 9. METERING & VISUALIZATION

### 9.1 Level Meters

**Types:**

| Meter Type | Karakteristike |
|------------|----------------|
| Peak | Instantaneous peak |
| Peak + VU | Combined display |
| Peak + RMS | Combined display |
| VU | Average level |
| PPM | Broadcast standard |

**Scales:**

| Scale | Range | Standard |
|-------|-------|----------|
| Digital (dBFS) | -inf to 0 | Digital standard |
| Digital +3 | -inf to +3 | Extended headroom display |
| DIN | -50 to +5 | German broadcast |
| EBU | -18 to +18 | European broadcast |
| British | -18 to +12 | BBC standard |
| Nordic | -42 to +12 | Scandinavian |
| K-12 | K-metering | Mastering |
| K-14 | K-metering | Mixing |
| K-20 | K-metering | Tracking |

### 9.2 SuperVision (Analysis Plugin)

**Specifikacije:**

| Feature | Vrednost |
|---------|----------|
| Modules | 18 |
| Sidechain Input | Da |
| Resizable | Da |

**Available Modules:**

| Module | Tip | Funkcija |
|--------|-----|----------|
| Level Meter | Metering | Peak/RMS levels |
| Loudness | Metering | LUFS, LRA |
| Wavescope | Waveform | Real-time waveform |
| Spectrum Curve | FFT | Frequency analysis |
| Spectrum | FFT | Spectrogram |
| Spectrogram | FFT | Time-frequency |
| Phase Meter | Correlation | L/R correlation |
| Direction | Spatial | Sound direction |
| Surround | Spatial | Surround levels |

**Loudness Metering:**

| Measurement | Spec | Window |
|-------------|------|--------|
| Momentary Max | ITU-R BS.1770 | 400ms |
| Short-Term | ITU-R BS.1770 | 3 sec |
| Integrated | ITU-R BS.1770 | Full playback |
| Loudness Range | EBU R128 | Dynamic range |
| True Peak | ITU-R BS.1770 | Inter-sample |

**Masking Analysis:**
- Side-chain input
- Highlights masked frequencies
- Visual overlay

### 9.3 Loudness Meter (Control Room)

**Measurements:**
- Integrated LUFS
- True Peak
- Short-term LUFS
- Momentary LUFS
- Loudness Range

**Targets:**

| Platform | Integrated | True Peak |
|----------|------------|-----------|
| Spotify | -14 LUFS | -1 dBTP |
| Apple Music | -16 LUFS | -1 dBTP |
| YouTube | -14 LUFS | -1 dBTP |
| Broadcast (EBU) | -23 LUFS | -1 dBTP |
| Broadcast (ATSC) | -24 LKFS | -2 dBTP |

### 9.4 Spectrum Analyzer

**In-Channel EQ:**
- Pre/Post EQ display
- FFT analysis
- Adjustable slope display

**SuperVision Spectrum:**
- High-resolution FFT
- Adjustable FFT size
- Peak hold
- Averaging

### 9.5 Phase Correlation

**Displays:**
- -1 to +1 correlation
- Stereo width visualization
- Mono compatibility check

---

## 10. UI/UX DESIGN

### 10.1 Workspaces

**Features:**
- Save window arrangements
- Keyboard shortcuts za recall
- Global vs Project-specific
- Multiple configurations

**Workflow:**
- Create layouts za razlicite tasks
- Tracking workspace
- Mixing workspace
- Editing workspace
- Mastering workspace

### 10.2 Lower Zone

**Tabs:**

| Tab | Sadrzaj |
|-----|---------|
| MixConsole | Full mixer (v14 novo) |
| Editor | Selected event editor |
| Sampler Control | Sampler Track controls |
| Chord Pads | Chord triggering |
| Modulators | Modulator controls (v14 novo) |
| Pattern Editor | Step sequencer (v14 novo) |

**Features:**
- Adjustable height
- Tab customization
- Editor follows selection

### 10.3 MixConsole Layouts

**Sections:**

| Section | Sadrzaj |
|---------|---------|
| Left Zone | Channel selectors, history |
| Fader Area | Channel strips |
| Right Zone | Control Room, Meter |
| Racks | Routing, Inserts, Sends, EQ |

**Visibility:**
- Configurations (save/recall)
- Filter by track type
- Sync sa Project Window

**Cubase 14 New:**
- Full MixConsole in Lower Zone
- Drag-and-drop channel reordering

### 10.4 Visibility Configurations

**Features:**
- Save channel visibility setups
- Up to 8 configurations
- Keyboard shortcuts
- Project-specific

**Use Cases:**
- Show only drums
- Show only vocals
- Show busses only
- Show everything

### 10.5 Color Schemes

**Customization:**
- Track colors
- Event colors
- Mixer colors
- Custom color palettes
- Color by track type

### 10.6 Keyboard Shortcuts

**Essential Shortcuts:**

| Shortcut | Funkcija |
|----------|----------|
| Space | Play/Stop |
| Enter (Numpad) | Return to zero |
| 1 (Numpad) | Go to left locator |
| 2 (Numpad) | Go to right locator |
| P | Set locators to selection |
| L | Cycle on/off |
| R | Record |
| M | Mute selected |
| S | Solo selected |
| F3 | Open MixConsole |
| Alt+F3 | MixConsole Lower Zone |
| E | Open editor |
| Ctrl/Cmd+Z | Undo |
| Ctrl/Cmd+S | Save |
| Ctrl/Cmd+D | Duplicate |
| Ctrl/Cmd+K | Duplicate shared |
| J | Snap on/off |
| Q | Quantize |
| A | Auto-scroll |

**Navigation:**

| Shortcut | Funkcija |
|----------|----------|
| G | Zoom out |
| H | Zoom in |
| Shift+G | Zoom out vertical |
| Shift+H | Zoom in vertical |
| F | Full zoom out |
| Shift+F | Zoom to selection |
| Arrow keys | Navigate |
| Ctrl+Arrow | Navigate by bar |

### 10.7 Touch/Pen Support

**Features:**
- Multi-touch gestures
- Pinch to zoom
- Touch-friendly controls
- Pen input support
- Surface Pro compatible

---

## 11. COLLABORATION & INTEGRATION

### 11.1 VST Connect

**Features:**
- Real-time remote recording
- Video chat
- Talkback
- Cue mixes to remote
- High-quality audio transfer
- Built-in plugin

**Components:**
- VST Connect SE (included)
- VST Connect Pro (paid upgrade)
- VST Connect Performer (free, remote side)

### 11.2 AAF/OMF Support

**AAF (Advanced Authoring Format):**
- Import: Da
- Export: Da
- Availability: Artist & Pro

**OMF (Open Media Framework):**
- Import: Da
- Export: Da
- Availability: Pro only

**Considerations:**
- ProTools compatibility issues
- Metadata handling varies
- Prefer AAF over OMF
- Alternative: Rendered stems + MIDI

### 11.3 Video Engine

**Supported Codecs:**
- H.264
- H.265/HEVC
- ProRes
- DNxHD/HR
- MPEG-2
- Various Windows codecs

**Features:**
- Video track
- Frame-accurate sync
- Thumbnail generation
- Extract audio
- Timecode support

**Limitations vs Nuendo:**
- Cubase ima basic video support
- Nuendo ima advanced post-production features

### 11.4 External Sync

**Supported Protocols:**

| Protocol | Direction | Use Case |
|----------|-----------|----------|
| MTC (MIDI Time Code) | In/Out | Video sync |
| MIDI Clock | In/Out | Tempo sync |
| ASIO Positioning | In | Sample-accurate |
| VST System Link | Both | Multi-computer |

**Timecode Formats:**
- 23.976 fps
- 24 fps
- 25 fps
- 29.97 fps (Drop/Non-drop)
- 30 fps

### 11.5 Control Surfaces

**Protocols:**

| Protocol | Kontroleri |
|----------|------------|
| Mackie Control | Universal control |
| HUI | Pro Tools controllers |
| Generic Remote | Custom mapping |
| Quick Controls | Parameter focus |
| VST System Link | Multi-DAW |

**Native Support:**
- CC121 (Steinberg)
- CMC series (Steinberg)
- Nektar Panorama
- Many third-party

---

## 12. UNIQUE FEATURES

### 12.1 ASIO-Guard (Deep Dive)

**Arhitektura:**

```
[Audio Stream] → [Is Live Input?]
                      │
              ┌───────┴───────┐
              ↓               ↓
         [Real-time Path] [ASIO-Guard Path]
              │               │
         [Small Buffer]  [Large Buffer]
         [Immediate]     [Prefetch Queue]
              │               │
              └───────┬───────┘
                      ↓
               [Audio Output]
```

**Real-time Path:**
- Record-enabled tracks
- Monitoring tracks
- Live MIDI input VSTi
- Processing mora zavrsiti unutar buffer window-a

**ASIO-Guard Path:**
- Svi ostali tracks
- Pre-renders sa vecim buffer-om
- Rezultat ide u prefetch queue
- Vise vremena za kompleksne plug-in-e

**Dynamic Switching:**
- Enable monitoring → Real-time
- Disable monitoring → ASIO-Guard
- Instant prebacivanje

### 12.2 Direct Routing (Cubase Pro)

**Summing Modes:**

| Mode | Behavior |
|------|----------|
| Exclusive | One destination at a time |
| Summing | Multiple simultaneous |

**Use Cases:**
- Stem creation
- Alternative mixes
- Live switching
- Broadcast routing

**Automation:**
- Automate destination switches
- Scene-based mixing
- Timeline-based routing

### 12.3 Control Room

**Funkcija:** Professional monitoring section

**Components:**

| Component | Funkcija |
|-----------|----------|
| Monitor Channels | Up to 4 monitor sets |
| Cue Channels | Up to 4 cue mixes |
| Headphone | Dedicated headphone out |
| Talkback | Mic for communication |
| External Inputs | Source monitoring |

**Monitor Features:**
- Reference level presets
- Dim function
- Mono check
- Downmix preview
- Insert slots
- Click on/off per output

**Cue Mix Features:**
- Independent mix per cue
- Talkback routing
- Click routing
- Level control
- Pan control

### 12.4 Render in Place

**Options:**

| Option | Rezultat |
|--------|----------|
| Dry | No processing |
| Channel Settings | With inserts, EQ |
| Complete Signal Path | Full routing |

**Features:**
- Creates new track
- Mutes original
- Keeps automation
- Copy sends option
- Tail size option

### 12.5 Sampler Track

**Features:**
- Drag any audio to create instrument
- Automatic pitch detection
- Loop modes
- Envelope (filter, amp, pitch)
- LFO
- Filter section
- One-shot mode
- MediaBay integration

### 12.6 Drum Track (Cubase 14 novo)

**Drum Machine:**

| Feature | Specifikacija |
|---------|---------------|
| Pads | 128 (8 banks x 16) |
| Layers per Pad | 4 |
| Sample Modules | Da |
| Synth Modules | 38 (7 kategorija) |
| Choke Groups | 32 |
| Outputs | 32 individual + stereo |

**Synth Module Categories:**
1. Kick drums
2. Snares
3. Hi-hats
4. Toms
5. Cymbals
6. Percussion
7. Effects

### 12.7 Pattern Editor (Cubase 14 novo)

**Features:**

| Feature | Specifikacija |
|---------|---------------|
| Step Resolution | Adjustable |
| Pattern Length | Adjustable |
| Play Direction | Per-lane |
| Euclidean | Da |
| Probability | Per-step |
| Velocity | Per-step |
| Offset | Per-step |
| Repeats | Per-step |
| Gate | Per-step |
| Variance | Per-step |

**Compatible Tracks:**
- Drum Track
- Instrument Track
- MIDI Track
- Sampler Track

### 12.8 Modulators (Cubase 14 novo - Pro Only)

**Available Modulators:**

| Modulator | Funkcija |
|-----------|----------|
| LFO | Oscillating modulation |
| Envelope Follower | Audio-driven modulation |
| Shaper | Custom envelope |
| Macro Knob | Manual control |
| Step Modulator | Pattern-based |
| ModScripter | JavaScript-based |

**Specifications:**
- 8 slots per track
- 8 connections per slot
- Unipolar/Bipolar routing
- Any automatable parameter target

**ModScripter:**
- JavaScript scripting
- Custom modulation curves
- Algorithmic modulation
- Advanced users

### 12.9 Score Editor (Cubase 14 - Dorico Technology)

**Improvements:**
- Modern notation rendering
- Better playback integration
- Cleaner layout
- Export to Dorico za full notation

**Practical Focus:**
- Lead sheets
- Chord charts
- Basic notation
- Not full engraving (use Dorico)

---

## 13. TEHNICKE RAZLIKE: CUBASE vs NUENDO

| Feature | Cubase Pro 14 | Nuendo 14 |
|---------|---------------|-----------|
| Max Sample Rate | 192 kHz | 384 kHz |
| Max Surround | 7.1.4 | 22.2+ |
| Dolby Atmos Beds | 1 | Multiple |
| External Renderer | Ne | Da |
| ADM Import | Ne | Da |
| MPEG-H | Ne | Da |
| Video Editor | Ne | Da |
| BWF Metadata | Basic | Advanced |
| Field Recorder Import | Ne | Da |
| dearVR Spatial | Ne | Da |
| Game Audio Connect | Ne | Da |
| Advanced ADR | Ne | Da |
| ReConform | Ne | Da |
| Direct Offline + | Ne | Da |
| Loudness (Full) | Ne | Da |

---

## 14. PLUGIN COUNT SUMMARY

**Cubase Pro 14 Stock Plugins:**

| Kategorija | Broj |
|------------|------|
| Audio Effects | 90+ |
| MIDI Effects | 18 |
| VST Instruments | 8+ |
| Total Sounds | 3000+ |

**Notable Instruments:**
- HALion Sonic SE
- Groove Agent SE
- Padshop
- Retrologue
- Backbone
- Drum Machine (novo)

---

## 15. SYSTEM REQUIREMENTS

### Windows

| Component | Minimum | Preporuceno |
|-----------|---------|-------------|
| OS | Windows 10/11 64-bit | Latest Windows 11 |
| CPU | Intel/AMD multi-core | 8+ cores, 3.5+ GHz |
| RAM | 8 GB | 32 GB+ |
| Disk | SSD, 70 GB | NVMe SSD, 500 GB+ |
| Display | 1920x1080 | 4K |
| Audio | ASIO compatible | Professional interface |

### macOS

| Component | Minimum | Preporuceno |
|-----------|---------|-------------|
| OS | macOS 12+ | Latest macOS |
| CPU | Intel ili Apple Silicon | M1 Pro/Max/Ultra, M2+ |
| RAM | 8 GB | 32 GB+ |
| Disk | SSD, 70 GB | NVMe, 500 GB+ |
| Display | 1920x1080 | 4K+ |
| Audio | CoreAudio | Professional interface |

---

## 16. REFERENTNI LINKOVI

**Oficial Documentation:**
- [Steinberg Help - Cubase Pro 14](https://www.steinberg.help/r/cubase-pro/14.0/en/)
- [Steinberg Plugin Reference](https://www.steinberg.help/r/cubase-pro/cubaseplugref/14.0/en/)
- [ASIO-Guard Technical Details](https://helpcenter.steinberg.de/hc/en-us/articles/206103564)

**Sound On Sound Reviews:**
- [Cubase Pro 14 Review](https://www.soundonsound.com/reviews/steinberg-cubase-pro-14)
- [Frequency EQ Tutorial](https://www.soundonsound.com/techniques/cubase-pro-frequency-eq)
- [VariAudio 3 Tutorial](https://www.soundonsound.com/techniques/cubase-pro-variaudio-3-smart-controls)
- [Control Room Guide](https://www.soundonsound.com/techniques/control-room-0)

**MusicTech Tutorials:**
- [Channel Strip Processors](https://musictech.com/tutorials/cubase/cubase-channel-strip-processors/)
- [Distortion Effects Guide](https://musictech.com/tutorials/understanding-cubases-distortion-effects-and-when-to-use-each-of-them/)
- [Reverbs Guide](https://musictech.com/tutorials/understand-reverence-revelation-and-roomworks-reverbs-in-cubase/)

**Steinberg Forums:**
- [Official Steinberg Forums](https://forums.steinberg.net/)

---

*Dokument generisan: Januar 2026*
*Za implementaciju: FluxForge Studio*
