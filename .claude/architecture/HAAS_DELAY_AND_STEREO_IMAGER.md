# Haas Delay & Stereo Imager — Architecture Specification

**Created:** 2026-02-22
**Status:** 📋 PLANNED
**Priority:** P0 (StereoImager fix) + P1 (Haas Delay new)
**Reference:** iZotope Ozone Imager (gold standard), Pro Tools (AIR Stereo Width), Cubase (StereoEnhancer), Logic Pro (Direction Mixer)
**Target Quality:** iZotope Ozone Imager level ili bolji — multiband, vectorscope, stereoize, correlation

---

## 1. Executive Summary

Dva povezana ali različita stereo processing feature-a:

| Feature | Tip | Svrha | Status |
|---------|-----|-------|--------|
| **StereoImager** | Channel strip processing | M/S width, balance, rotation, correlation | ❌ EXISTS but DISCONNECTED from audio |
| **Haas Delay** | Insert processor | Precedence effect widening (1-30ms delay on L or R) | ❌ NOT IMPLEMENTED |

**StereoImager** je per-track/per-bus stereo processing koji pripada u signal chain (kao u Cubase/Pro Tools).
**Haas Delay** je specijalistički insert efekat koji se učitava po potrebi.

---

## 2. Problem: StereoImager Disconnect

### Trenutno stanje

```
STEREO_IMAGERS HashMap (ffi.rs:9557)     playback.rs
├── stereo_imager_create()                ├── process_pre_fader()  ← NO StereoImager call
├── stereo_imager_set_width()             ├── fader + pan
├── stereo_imager_set_pan()               ├── process_post_fader() ← NO StereoImager call
├── stereo_imager_set_balance()           └── bus summing
├── stereo_imager_set_mid_gain()
├── stereo_imager_set_side_gain()
├── stereo_imager_set_rotation()
├── stereo_imager_enable_width()
├── stereo_imager_enable_ms()
├── stereo_imager_enable_rotation()
├── stereo_imager_get_correlation()
└── stereo_imager_reset()
    ↓
    WRITES TO HashMap — AUDIO THREAD NEVER READS IT
```

**15+ FFI funkcija postoje** u `ffi.rs:9557-9745` ali `playback.rs` ih **nikada ne poziva**.

### Root Cause

`StereoImager` je kreiran kao standalone utility sa sopstvenim HashMap storage-om (`STEREO_IMAGERS`), identično kao prethodni bug sa `DYNAMICS_COMPRESSORS` koji je popravljen u P1.7 (2026-01-23). Audio thread čita samo `InsertProcessor` chain i per-track state u `PlaybackEngine`.

---

## 3. Solution Architecture

### 3.1 StereoImager — Ugradi u playback signal chain

**Pozicija u signal flow-u (SSL kanonski):**

```
Input
    ↓
Pre-Fader Inserts (EQ, Comp, Gate)
    ↓
Fader (volume)
    ↓
Pan (StereoPanner — već postoji u playback.rs)
    ↓
★ STEREO IMAGER (width, M/S, balance, rotation) ← NOVO
    ↓
Post-Fader Inserts (Reverb, Delay, Haas)
    ↓
Sends
    ↓
Bus Summing → Master
```

**Zašto posle Pan-a, pre Post-Fader Inserts:**
- Width mora da radi na pan-ovanom signalu (širi stereo image POSLE pan pozicioniranja)
- Post-fader inserts (reverb, delay) treba da prime widened signal
- Ovo je identično sa Cubase StereoEnhancer pozicijom
- Pro Tools AIR Stereo Width je insert ali konceptualno radi isto

**Implementacija — Dva pristupa (OBA su potrebna):**

#### Pristup A: Per-Track StereoImager u PlaybackEngine (channel strip feature)

Svaki track/bus/master dobija sopstveni `StereoImager` instance u `PlaybackEngine`:

```rust
// playback.rs — dodati u TrackState ili kao novi storage
struct TrackStereoImager {
    imager: StereoImager,
    enabled: bool,
}

// U process_track(), POSLE fader+pan, PRE post-fader inserts:
if track_imager.enabled {
    for i in 0..frames {
        let (l, r) = track_imager.imager.process_sample(track_l[i], track_r[i]);
        track_l[i] = l;
        track_r[i] = r;
    }
}
```

Ovo daje svakom kanalu "Width" knob u Channel Tab-u — kao Cubase/Pro Tools.

#### Pristup B: StereoImager kao InsertProcessor (plugin)

Za korisnike koji žele da ga ručno ubace u specifični slot:

```rust
// dsp_wrappers.rs
pub struct StereoImagerWrapper {
    inner: StereoImager,
    // Params:
    // 0 = width (0.0-2.0)
    // 1 = balance (-1.0 to +1.0)
    // 2 = mid_gain (dB)
    // 3 = side_gain (dB)
    // 4 = rotation (degrees)
    // 5 = width_enabled (0/1)
    // 6 = ms_enabled (0/1)
    // 7 = rotation_enabled (0/1)
}

impl InsertProcessor for StereoImagerWrapper { ... }
```

Registracija: `"stereo-imager" | "width" | "stereo-width"` u `create_processor_extended()`

### 3.2 Haas Delay — Novi InsertProcessor

**Haas delay** je specijalistički efekat — uvek kao insert, nikada kao channel strip feature.

```rust
// rf-dsp/src/spatial.rs (ili novi fajl rf-dsp/src/haas.rs)
pub struct HaasDelay {
    delay_buffer_l: Vec<f64>,    // Ring buffer za levi kanal
    delay_buffer_r: Vec<f64>,    // Ring buffer za desni kanal
    buffer_len: usize,           // Max delay samples (30ms @ 384kHz = 11520)
    write_pos: usize,
    delay_samples: usize,        // Current delay in samples
    delay_ms: f64,
    sample_rate: f64,
    delayed_channel: DelayedChannel,
    mix: f64,                    // Wet/dry (usually 1.0)
    enabled: bool,
    // Bonus: low-pass filter on delayed signal za natural sound
    lp_filter: Option<BiquadTDF2>,
    lp_enabled: bool,
    lp_frequency: f64,           // 2kHz-20kHz
}

pub enum DelayedChannel {
    Left,
    Right,
}
```

**Parametri (7 total):**

| # | Param | Range | Default | Opis |
|---|-------|-------|---------|------|
| 0 | `delay_ms` | 0.1–30.0 | 0.0 | Delay time |
| 1 | `delayed_channel` | 0=Left, 1=Right | 1 (Right) | Koji kanal kasni |
| 2 | `mix` | 0.0–1.0 | 1.0 | Wet/dry blend |
| 3 | `lp_enabled` | 0/1 | 0 | Low-pass na delayed signal |
| 4 | `lp_frequency` | 2000–20000 Hz | 8000 | LP cutoff |
| 5 | `feedback` | 0.0–0.5 | 0.0 | Opcioni feedback (za kreativni efekat) |
| 6 | `phase_invert` | 0/1 | 0 | Invert delayed channel phase |

**Zašto LP filter:** Realni Haas efekat u sobi ima HF roll-off na reflektovanom zvuku. LP filter čini widening prirodnijim i smanjuje comb filtering artefakte u mono.

**Zašto feedback:** Na 0.0 je čist Haas. Na 0.1-0.3 daje bogatu, chorus-like texturu. Pro alati (Waves S1, iZotope Ozone Imager) imaju sličan parametar.

**InsertProcessor wrapper:**

```rust
// dsp_wrappers.rs
pub struct HaasDelayWrapper {
    inner: HaasDelay,
    sample_rate: f64,
}

impl InsertProcessor for HaasDelayWrapper {
    fn process_block(&mut self, left: &mut [f64], right: &mut [f64]) {
        self.inner.process_block(left, right);
    }
    fn set_param(&mut self, index: usize, value: f64) { ... }
    fn get_param(&self, index: usize) -> f64 { ... }
    fn param_count(&self) -> usize { 7 }
    fn name(&self) -> &str { "FluxForge Haas Delay" }
    fn latency_samples(&self) -> u32 { 0 } // No latency compensation needed
}
```

Registracija: `"haas-delay" | "haas" | "haas_delay" | "stereo-widener" | "precedence"` u `create_processor_extended()`

---

## 4. Signal Flow — Kompletna slika

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  PER-TRACK CHAIN                     │
                    ├─────────────────────────────────────────────────────┤
                    │                                                     │
                    │  Audio Input                                        │
                    │      ↓                                              │
                    │  Input Gain Trim (±20dB)                            │
                    │      ↓                                              │
                    │  ┌─── PRE-FADER INSERTS ───┐                       │
                    │  │  Slot 0: EQ (ProEq)     │                       │
                    │  │  Slot 1: Compressor      │                       │
                    │  │  Slot 2: Gate            │                       │
                    │  │  Slot N: ...             │                       │
                    │  └──────────────────────────┘                       │
                    │      ↓                                              │
                    │  FADER (volume, FaderCurve)                         │
                    │      ↓                                              │
                    │  PAN (StereoPanner, pan law)                        │
                    │      ↓                                              │
                    │  ★ STEREO IMAGER (width, M/S, balance, rotation)   │ ← CHANNEL STRIP FEATURE
                    │      ↓                                              │
                    │  ┌─── POST-FADER INSERTS ──┐                       │
                    │  │  Slot 0: Reverb          │                       │
                    │  │  Slot 1: Delay           │                       │
                    │  │  Slot 2: Haas Delay ★    │ ← INSERT PROCESSOR   │
                    │  │  Slot N: ...             │                       │
                    │  └──────────────────────────┘                       │
                    │      ↓                                              │
                    │  SENDS (Aux)                                        │
                    │      ↓                                              │
                    │  → BUS SUMMING                                      │
                    └─────────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────────────┐
                    │                   MASTER BUS                        │
                    ├─────────────────────────────────────────────────────┤
                    │  Pre-Fader Inserts                                  │
                    │      ↓                                              │
                    │  Master Fader                                       │
                    │      ↓                                              │
                    │  ★ MASTER STEREO IMAGER                             │
                    │      ↓                                              │
                    │  Post-Fader Inserts (incl. optional Haas)           │
                    │      ↓                                              │
                    │  Output                                             │
                    └─────────────────────────────────────────────────────┘
```

---

## 5. iZotope Ozone Imager — Feature Parity & Beyond

### 5.0 Ozone Imager Feature Analysis

| Ozone Imager Feature | FluxForge Equivalent | Status |
|----------------------|---------------------|--------|
| **4-band multiband width** | `MultibandStereoImager` | 📋 PLANNED (novo) |
| **Per-band width slider** (-100 to +100) | Per-band `StereoWidth` | 📋 PLANNED |
| **Stereoize** (mono→stereo synthesis) | `Stereoize` mode (Haas + decorrelation) | 📋 PLANNED |
| **Polar Sample Vectorscope** | `VectorscopeWidget` (Lissajous) | 📋 PLANNED |
| **Polar Level Vectorscope** | `VectorscopeWidget` (Polar rays) | 📋 PLANNED |
| **Lissajous display** | `VectorscopeWidget` (XY plot) | 📋 PLANNED |
| **Correlation Meter** | `CorrelationMeter` (već postoji u rf-dsp) | ✅ EXISTS (DSP) |
| **Crossover mini-spectrum** | Crossover frequency display | 📋 PLANNED |
| **Link Bands** | Linked width sliders | 📋 PLANNED |
| **Width Spectrum** | Real-time stereo width per frequency | 📋 PLANNED (P2) |

### 5.0.1 Gde FluxForge IDE DALJE od Ozone

| FluxForge Exclusive | Opis |
|---------------------|------|
| **Channel strip integration** | Width kontrola direktno na svakom kanalu (Ozone je samo plugin) |
| **Haas Delay mode** | Ozone nema dedicated Haas — FluxForge ima oba pristupa |
| **Per-track + Master** | Isti imager na svim nivoima (track, bus, master) |
| **M/S processing** sa mid/side gain | Ozone ima width only, nema independent M/S gain |
| **Stereo Rotation** | Ozone nema — FluxForge ima (iz StereoImager) |
| **A/B snapshots** | FabFilter-style A/B comparison |

### 5.0.2 MultibandStereoImager — Rust DSP

```rust
// rf-dsp/src/spatial.rs — NOVO
pub struct MultibandStereoImager {
    // 4 bands (Ozone standard)
    bands: [BandImager; 4],
    crossovers: [f64; 3],          // 3 crossover frequencies
    crossover_filters: [LinkwitzRileyFilter; 3],  // 24dB/oct
    linked: bool,
    stereoize_amount: f64,          // 0.0-1.0
    stereoize_enabled: bool,
    correlation: CorrelationMeter,
    sample_rate: f64,
}

pub struct BandImager {
    width: StereoWidth,             // -1.0 (mono) to 2.0 (extra wide)
    // Ozone range: -100 to +100 → normalize to -1.0 to +2.0
    enabled: bool,
}

// Crossover defaults (Ozone-style):
// Band 1: 0 Hz – 200 Hz      (sub/bass — usually narrow)
// Band 2: 200 Hz – 2 kHz     (low-mid)
// Band 3: 2 kHz – 8 kHz      (presence)
// Band 4: 8 kHz – 20 kHz     (air — usually widened)
```

**Stereoize Mode:**
Ozone's "Stereoize" adds width to mono/narrow signals via allpass-based decorrelation:

```rust
pub struct Stereoize {
    allpass_chain_l: [AllpassFilter; 4],
    allpass_chain_r: [AllpassFilter; 4],
    amount: f64,  // 0.0-1.0
    // Different allpass coefficients per channel create
    // decorrelation without comb filtering artifacts
}
```

**InsertProcessor wrapper (multiband):**

```rust
// dsp_wrappers.rs
pub struct MultibandImagerWrapper {
    inner: MultibandStereoImager,
    // Params (17 total):
    // 0-3:  band_width[0..3]     (-1.0 to 2.0)
    // 4-6:  crossover_freq[0..2] (20Hz-20kHz)
    // 7:    linked                (0/1)
    // 8:    stereoize_amount      (0.0-1.0)
    // 9:    stereoize_enabled     (0/1)
    // 10-13: band_enabled[0..3]  (0/1)
    // 14:   global_width          (0.0-2.0, affects all bands when linked)
    // 15:   output_gain           (dB)
    // 16:   mono_compat_check     (0/1, solo mono sum for checking)
}
```

Registracija: `"multiband-imager" | "ozone-imager" | "mb-stereo" | "mb-width"` u `create_processor_extended()`

### 5.0.3 Vectorscope Widget — Flutter

```dart
// flutter_ui/lib/widgets/metering/vectorscope_widget.dart
enum VectorscopeMode {
  polarSample,   // Ozone: dots per sample on polar display
  polarLevel,    // Ozone: rays showing average amplitude + position
  lissajous,     // Classic XY plot (L=X, R=Y)
}

class VectorscopeWidget extends StatefulWidget {
  final int trackId;
  final VectorscopeMode mode;
  final double size;  // Square widget
}
```

FFI za vectorscope data:
- Reuse `stereo_imager_get_correlation()` za correlation bar
- Novi FFI: `stereo_imager_get_vectorscope_data(trackId, numSamples)` → raw L/R pairs za rendering

---

## 5.1 Channel Tab — Width Knob (StereoImager)

U `_buildFaderPanSection()` (sekcija 4 po SSL ordering-u):

```
┌────────────────────────────────────┐
│ FADER + PAN                    ▼  │
├────────────────────────────────────┤
│ Volume: ──────────●────── -3.2 dB │
│ Pan:    ──────●──────────  L12    │
│ Width:  ────────────●────  1.35   │  ← NOVO (StereoImager.width)
│                                    │
│ [M] [S] [R] [I] [Ø]              │
└────────────────────────────────────┘
```

- Width knob range: 0.0 (mono) → 1.0 (normal) → 2.0 (extra wide)
- Default: 1.0
- Radi na svim kanalima: audio, bus, master
- Correlation meter u dnu (opciono, kompaktni bar)

### 5.2 FabFilter Panel — FF-HAAS (Haas Delay)

Otvara se kao floating editor window kad se Haas Delay učita u insert slot:

```
┌─────────────────────────────────────────────────────────────────┐
│  FF-HAAS — Stereo Widener              [A] [B]  [⊘]  [✕]      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   DELAY          CHANNEL        MIX          LP FILTER         │
│   ┌───────┐      ┌───────┐     ┌───────┐    ┌───────┐         │
│   │  8.5  │      │ RIGHT │     │ 100%  │    │ 8.0k  │         │
│   │  ms   │      │  ◄ ►  │     │       │    │  Hz   │         │
│   └───────┘      └───────┘     └───────┘    └───────┘         │
│   FabKnob        Toggle         FabKnob      FabKnob           │
│   0.1–30ms       L / R          0–100%       2k–20kHz          │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  CORRELATION  ←──────────[████████████]──────────────────→│  │
│  │  -1.0          0.0          +0.7          +1.0           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  HAAS ZONE  ████████████████░░░░░░░░░░░░░   8.5ms / 30ms      │
│             |── WIDE ──|── ECHO ──|── DELAY ──|                 │
│             0    10    15    20    25    30ms                    │
│                                                                 │
│  [FEEDBACK: 0%]  [PHASE: Normal]                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Zone indikator:**
- 0.1–10ms: Zeleno (WIDE) — čist Haas widening
- 10–15ms: Žuto (TRANSITION) — prelaz ka echo-u
- 15–25ms: Narandžasto (ECHO RISK) — echo počinje da se čuje
- 25–30ms: Crveno (DELAY) — jasan echo, ne Haas

### 5.3 FabFilter Panel — FF-IMG (StereoImager kao insert)

Za korisnike koji žele StereoImager kao insert (ne channel strip):

```
┌─────────────────────────────────────────────────────────────────┐
│  FF-IMG — Stereo Imager                [A] [B]  [⊘]  [✕]      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   WIDTH         BALANCE       MID GAIN      SIDE GAIN          │
│   ┌───────┐     ┌───────┐    ┌───────┐     ┌───────┐          │
│   │ 1.35  │     │  C    │    │ 0.0dB │     │+2.0dB │          │
│   └───────┘     └───────┘    └───────┘     └───────┘          │
│                                                                 │
│   ROTATION      [Width ✓] [M/S ✓] [Rotation ☐]                │
│   ┌───────┐                                                     │
│   │  0°   │                                                     │
│   └───────┘                                                     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  CORRELATION  ←──────────[████████████]──────────────────→│  │
│  │  -1.0          0.0          +0.8          +1.0           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  VECTORSCOPE                                              │  │
│  │       (Lissajous — opciono, P2)                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Implementation Plan — Task Breakdown

### Phase 1: StereoImager Fix (P0 — CRITICAL)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 1.1 | Add `StereoImager` field to per-track state in `playback.rs` | `playback.rs` | ~40 |
| 1.2 | Process StereoImager in track audio chain (post-pan, pre-post-inserts) | `playback.rs` | ~30 |
| 1.3 | Process StereoImager on bus chains | `playback.rs` | ~20 |
| 1.4 | Process StereoImager on master chain | `playback.rs` | ~15 |
| 1.5 | Redirect existing `stereo_imager_*` FFI functions to PLAYBACK_ENGINE | `ffi.rs` | ~80 |
| 1.6 | Remove STEREO_IMAGERS HashMap (dead code after redirect) | `ffi.rs` | -50 |
| 1.7 | Add Width slider to Channel Tab `_buildFaderPanSection()` | `channel_inspector_panel.dart` | ~30 |
| 1.8 | Add Width knob to UltimateMixer channel strip | `ultimate_mixer.dart` | ~25 |
| 1.9 | Wire width FFI calls from MixerProvider | `mixer_provider.dart` | ~20 |
| 1.10 | Create `StereoImagerWrapper` InsertProcessor | `dsp_wrappers.rs` | ~120 |
| 1.11 | Register `"stereo-imager"` in `create_processor_extended()` | `dsp_wrappers.rs` | ~5 |
| 1.12 | Add `DspNodeType.stereoImager` to enum | `dsp_chain_provider.dart` | ~5 |

**Phase 1 Total:** ~440 LOC, 12 tasks

### Phase 2: Haas Delay (P1 — HIGH)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 2.1 | Implement `HaasDelay` DSP struct | `rf-dsp/src/spatial.rs` | ~180 |
| 2.2 | Create `HaasDelayWrapper` InsertProcessor | `dsp_wrappers.rs` | ~120 |
| 2.3 | Register `"haas-delay"` in `create_processor_extended()` | `dsp_wrappers.rs` | ~5 |
| 2.4 | Add `DspNodeType.haasDelay` to enum | `dsp_chain_provider.dart` | ~5 |
| 2.5 | Create `fabfilter_haas_panel.dart` (FF-HAAS UI) | `widgets/fabfilter/` | ~450 |
| 2.6 | Wire into `InternalProcessorEditorWindow` registry | `internal_processor_editor_window.dart` | ~10 |
| 2.7 | Add Haas Delay A/B snapshot class | `fabfilter_haas_panel.dart` | ~40 |

**Phase 2 Total:** ~810 LOC, 7 tasks

### Phase 3: StereoImager FabFilter Panel (P1 — HIGH)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 3.1 | Create `fabfilter_imager_panel.dart` (FF-IMG UI) | `widgets/fabfilter/` | ~500 |
| 3.2 | Add A/B snapshot class for StereoImager | `fabfilter_imager_panel.dart` | ~60 |
| 3.3 | Wire into `InternalProcessorEditorWindow` registry | `internal_processor_editor_window.dart` | ~10 |

**Phase 3 Total:** ~570 LOC, 3 tasks

### Phase 4: MultibandStereoImager — iZotope Ozone Level (P1 — HIGH)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 4.1 | Implement `LinkwitzRileyFilter` (24dB/oct crossover) | `rf-dsp/src/spatial.rs` | ~120 |
| 4.2 | Implement `BandImager` struct (per-band width) | `rf-dsp/src/spatial.rs` | ~60 |
| 4.3 | Implement `MultibandStereoImager` struct (4-band + crossovers) | `rf-dsp/src/spatial.rs` | ~250 |
| 4.4 | Implement `Stereoize` allpass-chain decorrelation | `rf-dsp/src/spatial.rs` | ~150 |
| 4.5 | Create `MultibandImagerWrapper` InsertProcessor (17 params) | `dsp_wrappers.rs` | ~200 |
| 4.6 | Register `"multiband-imager"` in `create_processor_extended()` | `dsp_wrappers.rs` | ~5 |
| 4.7 | Add `DspNodeType.multibandImager` to enum | `dsp_chain_provider.dart` | ~5 |
| 4.8 | Create `fabfilter_multiband_imager_panel.dart` (FF-MBI UI) | `widgets/fabfilter/` | ~700 |
| 4.9 | Crossover frequency display with mini-spectrum | `fabfilter_multiband_imager_panel.dart` | ~150 |
| 4.10 | Band link toggle + global width control | `fabfilter_multiband_imager_panel.dart` | ~40 |
| 4.11 | A/B snapshot class for MultibandImager | `fabfilter_multiband_imager_panel.dart` | ~80 |
| 4.12 | Wire into `InternalProcessorEditorWindow` registry | `internal_processor_editor_window.dart` | ~10 |

**Phase 4 Total:** ~1,770 LOC, 12 tasks

### Phase 5: Vectorscope & Metering (P2 — MEDIUM)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 5.1 | Create `VectorscopeWidget` (3 modes: Polar Sample, Polar Level, Lissajous) | `widgets/metering/vectorscope_widget.dart` | ~500 |
| 5.2 | FFI: `stereo_imager_get_vectorscope_data(trackId, numSamples)` → raw L/R pairs | `ffi.rs` + `native_ffi.dart` | ~80 |
| 5.3 | Integrate vectorscope into FF-IMG and FF-MBI panels | `fabfilter_imager_panel.dart`, `fabfilter_multiband_imager_panel.dart` | ~40 |
| 5.4 | Real-time stereo width spectrum display (per-frequency width) | `widgets/metering/width_spectrum_widget.dart` | ~350 |

**Phase 5 Total:** ~970 LOC, 4 tasks

### Phase 6: Testing & Polish (P2 — MEDIUM)

| # | Task | Files | LOC est. |
|---|------|-------|----------|
| 6.1 | Unit tests for HaasDelay (mono compat, phase, edge cases) | `rf-dsp/tests/` | ~150 |
| 6.2 | Unit tests for StereoImager in signal chain | `rf-engine/tests/` | ~100 |
| 6.3 | Unit tests for MultibandStereoImager (crossover, per-band) | `rf-dsp/tests/` | ~180 |
| 6.4 | Unit tests for Stereoize decorrelation | `rf-dsp/tests/` | ~80 |
| 6.5 | Correlation meter widget for Channel Tab (compact bar) | `channel_inspector_panel.dart` | ~40 |
| 6.6 | Dart unit tests for all panel snapshots | `flutter_ui/test/` | ~120 |
| 6.7 | Mono compatibility check button on all stereo panels | `fabfilter_*.dart` | ~30 |

**Phase 6 Total:** ~700 LOC, 7 tasks

---

## 7. DAW Comparison

| Feature | Pro Tools | Cubase | Logic Pro | FluxForge (planned) |
|---------|-----------|--------|-----------|---------------------|
| **Per-channel width** | AIR Stereo Width (insert) | StereoEnhancer (channel strip) | Direction Mixer (insert) | ✅ Channel strip + insert |
| **M/S processing** | Plugin only | Plugin only | Direction Mixer | ✅ StereoImager (built-in) |
| **Haas delay** | Short Delay (plugin) | MonoToStereo (plugin) | Sample Delay (plugin) | ✅ FF-HAAS (built-in) |
| **Correlation meter** | Plugin only | Plugin only | Correlation meter (built-in) | ✅ StereoImager (built-in) |
| **Width on master** | Insert only | Insert only | Insert only | ✅ Channel strip + insert |

**FluxForge prednost:** Width je i channel strip feature I insert procesor. Cubase ima StereoEnhancer ali samo kao channel strip. Pro Tools nema built-in width — mora se koristiti plugin. FluxForge nudi oba pristupa.

---

## 8. FFI Summary

### Existing (redirect to PLAYBACK_ENGINE):

| FFI Function | Current Target | New Target |
|---|---|---|
| `stereo_imager_create` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_width` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_pan` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_balance` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_mid_gain` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_side_gain` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_set_rotation` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_enable_*` (5) | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_get_correlation` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |
| `stereo_imager_reset` | STEREO_IMAGERS HashMap | PLAYBACK_ENGINE per-track |

### New (Haas — via existing insert FFI):

Nema novih FFI funkcija. Haas Delay koristi:
- `insert_load_processor(trackId, slot, "haas-delay")`
- `insert_set_param(trackId, slot, paramIndex, value)`
- `insert_set_bypass(trackId, slot, bypass)`
- `track_insert_set_mix(trackId, slot, mix)`

---

## 9. Risk Assessment

| Risk | Mitigation |
|------|------------|
| StereoImager u audio thread koristi RwLock (STEREO_IMAGERS) | Eliminišemo HashMap — per-track field, no lock |
| Haas mono compatibility (phase cancellation) | LP filter + correlation meter warning |
| Performance (StereoImager on every track) | Per-sample M/S je trivijalan (~2 mul + 2 add), zanemarljiv CPU |
| Haas ring buffer memory | Max 30ms @ 384kHz = 11,520 samples × 8 bytes = ~92KB per instance |

---

## 10. Implementation Summary

| Phase | Focus | Tasks | LOC est. | Priority |
|-------|-------|-------|----------|----------|
| **Phase 1** | StereoImager Fix (channel strip + InsertProcessor) | 12 | ~440 | **P0 CRITICAL** |
| **Phase 2** | Haas Delay (DSP + InsertProcessor + UI) | 7 | ~810 | **P1 HIGH** |
| **Phase 3** | StereoImager FabFilter Panel (FF-IMG) | 3 | ~570 | **P1 HIGH** |
| **Phase 4** | MultibandStereoImager — iZotope Ozone Level | 12 | ~1,770 | **P1 HIGH** |
| **Phase 5** | Vectorscope & Metering | 4 | ~970 | **P2 MEDIUM** |
| **Phase 6** | Testing & Polish | 7 | ~700 | **P2 MEDIUM** |
| **TOTAL** | | **45** | **~5,260** | |

---

*Last Updated: 2026-02-22 — iZotope Ozone Imager parity + multiband + vectorscope + stereoize*
