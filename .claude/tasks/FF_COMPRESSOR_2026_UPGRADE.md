# FF Compressor 2026 — Pro-C 2 Class Upgrade

**Created:** 2026-02-15
**Status:** 🔴 NOT STARTED
**Estimated:** ~16-18h across 4 faza
**Risk:** LOW (zero breaking FFI — proširenje 8→25 params, svi stari indeksi kompatibilni)

---

## CILJ

Kompletna implementacija svih 17 features koji postoje u UI ili su potrebni za Pro-C 2 klasu.
Proširujemo CompressorWrapper sa 8 na 25 parametara + 5 metera.
Zadržavamo InsertProcessor integraciju, wrapper, FFI pipeline.

---

## NON-NEGOTIABLE

- Zero heap allocation u `process()` — audio thread sacred
- Backward-compatible FFI (prvih 8 indeksa nepromenjeni)
- SIMD-safe memory alignment
- Deterministic processing
- Zero breaking changes u CompressorWrapper trait impl
- Svi novi parametri imaju sane defaults (existing presets ne smeju se promeniti)

---

## FEATURE LISTA (17)

| # | Feature | UI State | FFI Index | Opis | LOC |
|---|---------|----------|-----------|------|-----|
| 1 | **Knee** | `_knee` (0-24 dB) | 8 | Soft-knee — postoji u Rust, wrapper ne expose-uje | ~5 |
| 2 | **Character** | `_character` (enum) | 9 | Saturation: Off=0, Tube=1, Diode=2, Bright=3 | ~200 |
| 3 | **Drive** | `_drive` (0-24 dB) | 10 | Saturation količina | — |
| 4 | **Range** | `_range` (-40 to 0 dB) | 11 | GR range limit | ~30 |
| 5 | **SC HP Freq** | `_scHpFreq` (20-500 Hz) | 12 | Sidechain high-pass | ~150 |
| 6 | **SC LP Freq** | `_scLpFreq` (1k-20kHz) | 13 | Sidechain low-pass | — |
| 7 | **SC Audition** | `_scAudition` (bool) | 14 | Listen sidechain signal | — |
| 8 | **Lookahead** | — (0-20 ms) | 15 | Transient lookahead buffer | ~120 |
| 9 | **SC EQ Mid Freq** | `_scEqMidFreq` | 16 | SC parametric EQ freq | — |
| 10 | **SC EQ Mid Gain** | `_scEqMidGain` | 17 | SC parametric EQ gain | — |
| 11 | **Auto-Threshold** | `_autoThreshold` | 18 | Auto threshold tracking | ~60 |
| 12 | **Auto-Makeup** | `_autoMakeup` | 19 | Auto makeup compensation | ~40 |
| 13 | **Detection Mode** | NOVO | 20 | Peak/RMS/Hybrid envelope | ~80 |
| 14 | **Adaptive Release** | NOVO | 21 | 2-stage fast+slow release | ~60 |
| 15 | **Host Sync BPM** | `_hostSync` | 22 | BPM-quantized release | ~100 |
| 16 | **Host Sync Note** | NOVO | 23 | Note value (1/4, 1/8, etc.) | — |
| 17 | **Mid/Side Mode** | NOVO | 24 | M/S processing | ~80 |

**Style Engine** — Dart-side presets (~200 LOC Dart), ZERO Rust. Svaki stil postavlja kombinaciju params 0-24.

**Extended Meters** — 5 metera (GR L/R + Input Peak + Output Peak + GR Max Hold), ~60 LOC.

---

## FAZA 1 — RUST DSP CORE (~7h)

### F1.1: Knee Exposure ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Problem:** `Compressor.knee_db` postoji (linija ~442), ali `CompressorWrapper` ga ne prosleđuje.

**Fix:** Samo wire-ovanje u F2 (Wrapper). DSP je spreman.

---

### F1.2: Character Saturation (~200 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Novi enum + fields u Compressor:**
```rust
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum CharacterMode {
    #[default]
    Off,     // Clean — no saturation
    Tube,    // Soft-clip, even harmonics (2nd, 4th)
    Diode,   // Asymmetric clip, odd harmonics (3rd)
    Bright,  // Pre-emphasis → clip → de-emphasis (high-freq saturation)
}

// U Compressor struct dodati:
character: CharacterMode,  // Default: Off
drive: f64,                // 0.0 - 24.0 dB, default: 0.0
emphasis_state: f64,       // 1-pole filter state za Bright mode
```

**Procesiranje (posle gain reduction, pre mix):**
```rust
fn apply_character(&mut self, sample: f64) -> f64 {
    if self.character == CharacterMode::Off || self.drive <= 0.0 {
        return sample;
    }
    let driven = sample * db_to_linear_fast(self.drive);
    match self.character {
        CharacterMode::Off => sample,
        CharacterMode::Tube => soft_clip_tube(driven),
        CharacterMode::Diode => soft_clip_diode(driven),
        CharacterMode::Bright => {
            // Pre-emphasis: boost highs (+6dB/oct @ ~3kHz)
            let coeff = 0.95;  // ~3kHz @ 48kHz
            let pre = driven - coeff * self.emphasis_state;
            self.emphasis_state = driven;
            // Clip
            let clipped = soft_clip_tube(pre);
            // De-emphasis: cut highs back
            clipped * coeff + self.emphasis_state * (1.0 - coeff)
        }
    }
}
```

**Tube:** `tanh(x)` Pade 3/3 aproksimacija:
```rust
#[inline(always)]
fn soft_clip_tube(x: f64) -> f64 {
    let x2 = x * x;
    x * (27.0 + x2) / (27.0 + 9.0 * x2)
}
```

**Diode:** Asimetrični clip:
```rust
#[inline(always)]
fn soft_clip_diode(x: f64) -> f64 {
    if x >= 0.0 {
        1.0 - (-x).exp()
    } else {
        -0.8 * (1.0 - x.exp())
    }
}
```

---

### F1.3: Range Limit (~30 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Novi field:**
```rust
range_db: f64,  // -40.0 to 0.0, default: -40.0 (no limit)
```

**Primena u `calculate_gain_reduction()`:**
```rust
// Posle izračunavanja gr_db, dodati:
let gr_clamped = gr_db.min(-self.range_db);  // range_db je negativan, GR je pozitivan
```

---

### F1.4: Sidechain Filters (~150 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Novi struct:**
```rust
struct SidechainFilter {
    hp: BiquadTDF2,
    lp: BiquadTDF2,
    eq_mid: BiquadTDF2,
    hp_freq: f64,          // 20-500 Hz, default: 20 (off)
    lp_freq: f64,          // 1k-20k Hz, default: 20000 (off)
    eq_freq: f64,          // 200-5000 Hz
    eq_gain: f64,          // -12 to +12 dB
    audition: bool,
    sample_rate: f64,
}

impl SidechainFilter {
    fn process(&mut self, input: f64) -> f64 {
        let mut s = self.hp.process(input);
        s = self.lp.process(s);
        s = self.eq_mid.process(s);
        s
    }
}
```

**SC Audition:** Kada je `audition=true`, output = SC signal.

---

### F1.5: Lookahead Buffer (~120 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

```rust
struct LookaheadBuffer {
    buffer_l: Vec<f64>,    // Pre-allocated, max 960 samples (20ms @ 48kHz)
    buffer_r: Vec<f64>,
    write_pos: usize,
    delay_samples: usize,
}
```

**Princip:** Audio delayed, sidechain undelayed → kompressor "vidi" transijeante unapred.
**Buffer se alocira u `new()`, NIKADA u `process()`.**
**PDC:** `latency_samples()` vraća `delay_samples`.

---

### F1.6: Auto-Threshold (~60 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

```rust
auto_threshold: bool,
input_level_rms: f64,

fn update_auto_threshold(&mut self, input_rms_db: f64) {
    if !self.auto_threshold { return; }
    let coeff = if input_rms_db > self.input_level_rms { 0.01 } else { 0.004 };
    self.input_level_rms += coeff * (input_rms_db - self.input_level_rms);
    let headroom = 6.0 + (self.ratio - 1.0) * 1.5;
    self.threshold_db = (self.input_level_rms - headroom).clamp(-60.0, 0.0);
}
```

---

### F1.7: Auto-Makeup Gain (~40 LOC) ⬜

```rust
auto_makeup: bool,

fn compute_auto_makeup(&self) -> f64 {
    if !self.auto_makeup { return 0.0; }
    let gr_estimate = -self.threshold_db * (1.0 - 1.0 / self.ratio) * 0.5;
    gr_estimate.clamp(0.0, 24.0)
}
```

---

### F1.8: Detection Mode — Peak/RMS/Hybrid (~80 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Novi enum + state:**
```rust
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum DetectionMode {
    #[default]
    Peak,    // abs(input) — fast, transient-sensitive
    Rms,     // sqrt(avg(x²)) — smooth, bus/mastering
    Hybrid,  // 50% peak + 50% RMS — Pro-C 2 default
}

// U Compressor struct:
detection_mode: DetectionMode,
rms_sum: f64,        // Running sum za RMS
rms_count: usize,    // Sample count
rms_window: usize,   // Window size (default: 128 samples)
```

**RMS kalkulacija (running average, zero-alloc):**
```rust
fn detect_level(&mut self, input: f64) -> f64 {
    match self.detection_mode {
        DetectionMode::Peak => input.abs(),
        DetectionMode::Rms => {
            self.rms_sum += input * input;
            self.rms_count += 1;
            if self.rms_count >= self.rms_window {
                let rms = (self.rms_sum / self.rms_window as f64).sqrt();
                self.rms_sum = 0.0;
                self.rms_count = 0;
                rms
            } else {
                // Return last computed RMS between windows
                self.envelope.current()
            }
        }
        DetectionMode::Hybrid => {
            let peak = input.abs();
            self.rms_sum += input * input;
            self.rms_count += 1;
            let rms = if self.rms_count >= self.rms_window {
                let r = (self.rms_sum / self.rms_window as f64).sqrt();
                self.rms_sum = 0.0;
                self.rms_count = 0;
                r
            } else {
                self.envelope.current()
            };
            peak * 0.5 + rms * 0.5
        }
    }
}
```

**Primena:** Zamenjuje `input.abs()` u svim `process_*()` metodama sa `self.detect_level(input)`.

---

### F1.9: Adaptive 2-Stage Release (~60 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Princip:** Dva envelope followera — fast za transijeante, slow za body. Blend baziran na envelope derivative.

```rust
// U Compressor struct:
adaptive_release: f64,         // 0.0 = off, 1.0 = full
fast_envelope: EnvelopeFollower,  // Short release (release_ms * 0.3)
slow_envelope: EnvelopeFollower,  // Long release (release_ms * 3.0)

fn process_adaptive_envelope(&mut self, input: f64) -> f64 {
    if self.adaptive_release <= 0.0 {
        return self.envelope.process(input);
    }

    let fast = self.fast_envelope.process(input);
    let slow = self.slow_envelope.process(input);

    // Blend: fast kad signal pada brzo (pumping), slow kad stabilan (glue)
    let delta = (fast - slow).abs();
    let blend = (delta * 10.0).min(1.0) * self.adaptive_release;

    fast * blend + slow * (1.0 - blend)
}
```

**Timing setup (u `set_release()`):**
```rust
fn set_release(&mut self, ms: f64) {
    self.release_ms = ms.clamp(1.0, 5000.0);
    self.envelope.set_times(self.attack_ms, self.release_ms);
    self.fast_envelope.set_times(self.attack_ms, self.release_ms * 0.3);
    self.slow_envelope.set_times(self.attack_ms, self.release_ms * 3.0);
}
```

---

### F1.10: Host Sync (~100 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Princip:** Kvantizuje release na note value baziran na BPM.

```rust
// U Compressor struct:
host_sync_bpm: f64,    // 0 = off, 60-200 = BPM
sync_note: SyncNote,

#[derive(Debug, Clone, Copy, Default)]
pub enum SyncNote {
    #[default]
    Quarter,     // 1/4
    Eighth,      // 1/8
    Sixteenth,   // 1/16
    QuarterDot,  // 1/4 dotted
    QuarterTrip, // 1/4 triplet
}

impl SyncNote {
    fn fraction(&self) -> f64 {
        match self {
            SyncNote::Quarter => 1.0,
            SyncNote::Eighth => 0.5,
            SyncNote::Sixteenth => 0.25,
            SyncNote::QuarterDot => 1.5,
            SyncNote::QuarterTrip => 2.0 / 3.0,
        }
    }
}

fn synced_release_ms(&self) -> f64 {
    if self.host_sync_bpm <= 0.0 { return self.release_ms; }
    // Quarter note duration = 60000 / BPM
    let quarter_ms = 60000.0 / self.host_sync_bpm;
    quarter_ms * self.sync_note.fraction()
}
```

**Primena:** Kada `host_sync_bpm > 0`, release se overriduje sa `synced_release_ms()`.
**Dart šalje BPM iz DAW transport-a.**

---

### F1.11: Mid/Side Mode (~80 LOC) ⬜

**Fajl:** `crates/rf-dsp/src/dynamics.rs`

**Princip:** Process u M/S domenu umesto L/R.

```rust
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ProcessingMode {
    #[default]
    Stereo,   // Normal L/R
    MidSide,  // M/S encoding → compress → decode
}

// U StereoCompressor:
processing_mode: ProcessingMode,
```

**M/S encode/decode u `process_sample()`:**
```rust
fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
    let (proc_l, proc_r) = match self.processing_mode {
        ProcessingMode::Stereo => (left, right),
        ProcessingMode::MidSide => {
            let mid = (left + right) * 0.5;
            let side = (left - right) * 0.5;
            (mid, side)
        }
    };

    // Compress
    let comp_l = self.left.process_sample(proc_l);
    let comp_r = self.right.process_sample(proc_r);

    // Linked detection (existing)
    // ...

    match self.processing_mode {
        ProcessingMode::Stereo => (comp_l, comp_r),
        ProcessingMode::MidSide => {
            // Decode back to L/R
            let out_l = comp_l + comp_r;  // Mid + Side
            let out_r = comp_l - comp_r;  // Mid - Side
            (out_l, out_r)
        }
    }
}
```

---

### F1.12: Extended Meters (~60 LOC) ⬜

**Fajl:** `crates/rf-engine/src/dsp_wrappers.rs`

**Novi meteri u CompressorWrapper:**
```rust
// State za metering
input_peak: f64,       // Max abs input
output_peak: f64,      // Max abs output
gr_max_hold: f64,      // Max GR sa decay
gr_hold_decay: f64,    // Decay rate za max hold
```

**Meter indeksi:**

| Index | Ime | Opis |
|-------|-----|------|
| 0 | GR Left | Gain reduction L (postojeći) |
| 1 | GR Right | Gain reduction R (postojeći) |
| 2 | Input Peak | Max input level (dB) |
| 3 | Output Peak | Max output level (dB) |
| 4 | GR Max Hold | Max GR sa 1s decay |

**`get_meter()` proširenje:**
```rust
fn get_meter(&self, index: usize) -> f64 {
    match index {
        0 => gr_l,
        1 => gr_r,
        2 => linear_to_db_fast(self.input_peak),
        3 => linear_to_db_fast(self.output_peak),
        4 => self.gr_max_hold,
        _ => 0.0,
    }
}
```

**Update u `process_stereo()`:**
```rust
// Track peaks
self.input_peak = self.input_peak.max(left.abs()).max(right.abs());
self.output_peak = self.output_peak.max(out_l.abs()).max(out_r.abs());

// GR max hold with decay
let gr = (gr_l + gr_r) * 0.5;
if gr > self.gr_max_hold {
    self.gr_max_hold = gr;
} else {
    self.gr_max_hold *= 0.9999;  // ~1s decay @ 48kHz
}

// Peak decay (per block)
self.input_peak *= 0.999;
self.output_peak *= 0.999;
```

---

## FAZA 2 — WRAPPER + FFI (~3h)

### F2.1: CompressorWrapper Param Expansion ⬜

**Fajl:** `crates/rf-engine/src/dsp_wrappers.rs`

**Trenutno (8 params):**

| Index | Ime | Raspon |
|-------|-----|--------|
| 0 | Threshold | -60 to 0 dB |
| 1 | Ratio | 1:1 to 20:1 |
| 2 | Attack | 0.01-300 ms |
| 3 | Release | 1-5000 ms |
| 4 | Makeup | -12 to +24 dB |
| 5 | Mix | 0.0-1.0 |
| 6 | Link | 0.0-1.0 |
| 7 | Type | 0=VCA, 1=Opto, 2=FET |

**Novo (25 params — prvih 8 nepromenjeni):**

| Index | Ime | Raspon | Default | Jedinica |
|-------|-----|--------|---------|----------|
| 0 | Threshold | -60 to 0 | -24.0 | dB |
| 1 | Ratio | 1.0-20.0 | 4.0 | :1 |
| 2 | Attack | 0.01-300 | 10.0 | ms |
| 3 | Release | 1-5000 | 100.0 | ms |
| 4 | Makeup | -12 to +24 | 0.0 | dB |
| 5 | Mix | 0.0-1.0 | 1.0 | — |
| 6 | Link | 0.0-1.0 | 1.0 | — |
| 7 | Type | 0/1/2 | 0.0 | enum |
| **8** | **Knee** | **0-24** | **6.0** | **dB** |
| **9** | **Character** | **0/1/2/3** | **0.0** | **enum** |
| **10** | **Drive** | **0-24** | **0.0** | **dB** |
| **11** | **Range** | **-40 to 0** | **-40.0** | **dB** |
| **12** | **SC HP Freq** | **20-500** | **20.0** | **Hz** |
| **13** | **SC LP Freq** | **1k-20k** | **20000.0** | **Hz** |
| **14** | **SC Audition** | **0.0/1.0** | **0.0** | **bool** |
| **15** | **Lookahead** | **0-20** | **0.0** | **ms** |
| **16** | **SC EQ Mid Freq** | **200-5k** | **1000.0** | **Hz** |
| **17** | **SC EQ Mid Gain** | **-12 to +12** | **0.0** | **dB** |
| **18** | **Auto-Threshold** | **0.0/1.0** | **0.0** | **bool** |
| **19** | **Auto-Makeup** | **0.0/1.0** | **0.0** | **bool** |
| **20** | **Detection Mode** | **0/1/2** | **0.0** | **enum** |
| **21** | **Adaptive Release** | **0.0-1.0** | **0.0** | **amount** |
| **22** | **Host Sync BPM** | **0/60-200** | **0.0** | **BPM** |
| **23** | **Sync Note** | **0-4** | **0.0** | **enum** |
| **24** | **Processing Mode** | **0/1** | **0.0** | **enum** |

**`num_params()` promjena:** `8 → 25`

**`set_param()` proširenje:**
```rust
8 => self.comp.set_knee(value),
9 => self.comp.set_character(value),
10 => self.comp.set_drive(value),
11 => self.comp.set_range(value),
12 => self.comp.set_sc_hp_freq(value),
13 => self.comp.set_sc_lp_freq(value),
14 => self.comp.set_sc_audition(value > 0.5),
15 => self.comp.set_lookahead(value),
16 => self.comp.set_sc_eq_freq(value),
17 => self.comp.set_sc_eq_gain(value),
18 => self.comp.set_auto_threshold(value > 0.5),
19 => self.comp.set_auto_makeup(value > 0.5),
20 => self.comp.set_detection_mode(value),
21 => self.comp.set_adaptive_release(value),
22 => self.comp.set_host_sync_bpm(value),
23 => self.comp.set_sync_note(value),
24 => self.comp.set_processing_mode(value),
```

**`get_param()` — KRITIČNO: trenutno vraća 0.0 za sve!**

Treba dodati stored params za SVE indekse:
```rust
fn get_param(&self, index: usize) -> f64 {
    match index {
        0 => self.params[0],  // threshold
        1 => self.params[1],  // ratio
        // ... sve do 24
        _ => 0.0,
    }
}
```

**Rešenje:** Dodati `params: [f64; 25]` u CompressorWrapper za get_param read-back.

---

### F2.2: Latency Reporting ⬜

```rust
fn latency_samples(&self) -> usize {
    self.comp.lookahead_samples()
}
```

---

## FAZA 3 — TESTOVI (~3h)

### F3.1: Unit Tests (~38 testova) ⬜

**Fajl:** `crates/rf-dsp/tests/compressor_tests.rs` (novi)

| Test | Verifikacija |
|------|-------------|
| `test_knee_0db_hard` | Knee=0 → hard knee |
| `test_knee_12db_soft` | Knee=12 → parabolic transition |
| `test_knee_24db_very_soft` | Knee=24 → wide transition |
| `test_character_off_clean` | Character=Off → bit-exact |
| `test_character_tube_harmonics` | Tube → even harmonics |
| `test_character_diode_asymmetry` | Diode → odd harmonics |
| `test_character_bright_presence` | Bright → HF content |
| `test_drive_0_no_effect` | Drive=0 → clean |
| `test_drive_24_heavy` | Drive=24 → heavy saturation |
| `test_range_0_no_compression` | Range=0 → no GR |
| `test_range_minus12_limited` | Range=-12 → max 12dB GR |
| `test_range_minus40_full` | Range=-40 → full (default) |
| `test_sc_hp_filter` | HP=200Hz → bass removed from SC |
| `test_sc_lp_filter` | LP=5kHz → highs removed from SC |
| `test_sc_audition` | Audition → output = SC signal |
| `test_sc_eq_boost` | EQ boost → more GR at freq |
| `test_sc_eq_cut` | EQ cut → less GR at freq |
| `test_lookahead_0ms` | Zero latency, same output |
| `test_lookahead_5ms` | Delayed audio, earlier GR |
| `test_lookahead_20ms_max` | Max delay, transient preservation |
| `test_auto_threshold_off` | Manual threshold unchanged |
| `test_auto_threshold_tracks` | Threshold follows input RMS |
| `test_auto_threshold_headroom` | Higher ratio → more headroom |
| `test_auto_makeup_off` | Manual makeup unchanged |
| `test_auto_makeup_compensates` | Output ≈ input level |
| `test_auto_makeup_formula` | Matches -thresh*(1-1/ratio)/2 |
| `test_detection_peak` | Peak mode = abs(input) |
| `test_detection_rms` | RMS mode = smoother GR |
| `test_detection_hybrid` | Hybrid = blend peak+RMS |
| `test_adaptive_release_off` | 0.0 → standard release |
| `test_adaptive_release_full` | 1.0 → 2-stage envelope |
| `test_adaptive_release_transient` | Fast decay on transients |
| `test_host_sync_off` | BPM=0 → manual release |
| `test_host_sync_120bpm_quarter` | 120BPM, 1/4 → 500ms release |
| `test_host_sync_120bpm_eighth` | 120BPM, 1/8 → 250ms release |
| `test_midside_stereo_default` | Stereo mode = normal L/R |
| `test_midside_encoding` | M/S encode → compress → decode |
| `test_backward_compat_8params` | Prvih 8 indeksa nepromenjeni |

### F3.2: Integration Tests (~8 testova) ⬜

| Test | Verifikacija |
|------|-------------|
| `test_wrapper_25_params` | `num_params() == 25`, set/get roundtrip |
| `test_get_param_readback` | Sve set_param → get_param roundtrip |
| `test_auto_threshold_wrapper` | param 18 toggles auto-threshold |
| `test_auto_makeup_wrapper` | param 19 toggles auto-makeup |
| `test_lookahead_latency_report` | `latency_samples()` correct |
| `test_detection_mode_wrapper` | param 20 switches detection |
| `test_midside_wrapper` | param 24 switches M/S |
| `test_extended_meters` | meters 0-4 all return valid values |

---

## FAZA 4 — UI WIRING + STYLE ENGINE (~3h)

### F4.1: Param Index Mapping ⬜

**Fajl:** `flutter_ui/lib/widgets/fabfilter/fabfilter_compressor_panel.dart`

```dart
void _applyAllParameters() {
  // Existing 0-7 unchanged
  _setParam(8, _knee);
  _setParam(9, _characterToValue(_character));
  _setParam(10, _drive);
  _setParam(11, _range);
  _setParam(12, _scHpFreq);
  _setParam(13, _scLpFreq);
  _setParam(14, _scAudition ? 1.0 : 0.0);
  _setParam(15, _lookahead);
  _setParam(16, _scEqMidFreq);
  _setParam(17, _scEqMidGain);
  _setParam(18, _autoThreshold ? 1.0 : 0.0);
  _setParam(19, _autoMakeup ? 1.0 : 0.0);
  _setParam(20, _detectionModeToValue(_detectionMode));
  _setParam(21, _adaptiveRelease);
  _setParam(22, _hostSync ? _hostBpm : 0.0);
  _setParam(23, _syncNoteToValue(_syncNote));
  _setParam(24, _midSide ? 1.0 : 0.0);
}
```

### F4.2: Read-back ⬜

```dart
void _readParamsFromEngine() {
  // Existing 0-7 unchanged
  _knee = _getParam(8);
  _character = _valueToCharacter(_getParam(9));
  _drive = _getParam(10);
  _range = _getParam(11);
  _scHpFreq = _getParam(12);
  _scLpFreq = _getParam(13);
  _scAudition = _getParam(14) > 0.5;
  _lookahead = _getParam(15);
  _scEqMidFreq = _getParam(16);
  _scEqMidGain = _getParam(17);
  _autoThreshold = _getParam(18) > 0.5;
  _autoMakeup = _getParam(19) > 0.5;
  _detectionMode = _valueToDetection(_getParam(20));
  _adaptiveRelease = _getParam(21);
  _hostBpm = _getParam(22);
  _hostSync = _hostBpm > 0;
  _syncNote = _valueToSyncNote(_getParam(23));
  _midSide = _getParam(24) > 0.5;
}
```

### F4.3: A/B Snapshot ⬜

Proširiti `CompressorSnapshot` sa svim novim parametrima.

### F4.4: Auto UI Behavior ⬜

Kada `_autoThreshold = true`:
- Threshold knob → `opacity: 0.3`, neaktivan
- `AUTO` badge iznad knoba
- Manualna vrednost čuvana u `_manualThreshold`

Kada `_autoMakeup = true`:
- Makeup knob → `opacity: 0.3`, neaktivan
- `AUTO` badge iznad knoba
- Manualna vrednost čuvana u `_manualMakeup`

### F4.5: Style Engine Presets (Dart-only, ~200 LOC) ⬜

**Nema Rust koda za stilove.** Svaki stil je preset koji postavlja params 0-24:

```dart
void _applyStylePreset(CompressionStyle style) {
  switch (style) {
    case CompressionStyle.clean:
      _setPreset(type: 0, attack: 10, release: 100, knee: 6,
        character: Off, detection: Peak, adaptive: 0);
    case CompressionStyle.classic:
      _setPreset(type: 0, attack: 10, release: 100, knee: 6,
        character: Off, detection: Peak, adaptive: 0.3);
    case CompressionStyle.opto:
      _setPreset(type: 1, attack: 30, release: 200, knee: 12,
        character: Off, detection: RMS, adaptive: 0.5);
    case CompressionStyle.vocal:
      _setPreset(type: 1, attack: 5, release: 80, knee: 12,
        character: Tube, drive: 3, detection: Hybrid, adaptive: 0.4);
    case CompressionStyle.mastering:
      _setPreset(type: 0, attack: 30, release: 200, knee: 18,
        range: -6, character: Off, detection: RMS, adaptive: 0.6);
    case CompressionStyle.bus:
      _setPreset(type: 0, attack: 10, release: 100, knee: 12,
        range: -12, character: Off, detection: Hybrid, adaptive: 0.3);
    case CompressionStyle.punch:
      _setPreset(type: 2, attack: 0.3, release: 50, knee: 3,
        character: Off, detection: Peak, adaptive: 0);
    case CompressionStyle.pumping:
      _setPreset(type: 0, attack: 0.1, release: 300, knee: 0,
        character: Off, detection: Peak, adaptive: 0, hostSync: true);
    case CompressionStyle.versatile:
      _setPreset(type: 0, attack: 10, release: 100, knee: 12,
        character: Off, detection: Hybrid, adaptive: 0.3);
    case CompressionStyle.smooth:
      _setPreset(type: 0, attack: 20, release: 200, knee: 18,
        character: Off, detection: RMS, adaptive: 0.7);
    case CompressionStyle.upward:
      _setPreset(type: 0, attack: 30, release: 150, knee: 12,
        range: -6, character: Off, detection: RMS, adaptive: 0.5);
    case CompressionStyle.variMu:
      _setPreset(type: 1, attack: 50, release: 300, knee: 24,
        character: Tube, drive: 6, detection: RMS, adaptive: 0.8);
    case CompressionStyle.elOp:
      _setPreset(type: 1, attack: 40, release: 250, knee: 18,
        character: Off, detection: RMS, adaptive: 0.6);
    case CompressionStyle.ttm:
      _setPreset(type: 2, attack: 0.5, release: 30, knee: 0,
        character: Diode, drive: 12, detection: Peak, adaptive: 0);
  }
  _applyAllParameters();
}
```

### F4.6: Nove UI Kontrole ⬜

**Dodati u panel:**

| Kontrola | Tip | Lokacija |
|----------|-----|----------|
| Detection Mode | Dropdown (Peak/RMS/Hybrid) | Pored Style dropdown-a |
| M/S toggle | Switch | Pored Detection |
| Adaptive Release | Slider (0-100%) | Ispod release knoba |
| Host Sync toggle | Switch | U Advanced sekciji |
| Sync Note selector | Dropdown (♩ ♪ ♬) | Pored Host Sync |
| Input Peak meter | Text | Meter sekcija |
| Output Peak meter | Text | Meter sekcija |
| GR Max Hold | Text + bar | GR meter sekcija |

### F4.7: Extended Meters UI ⬜

```dart
void _updateMeters() {
  // Existing GR meters
  _currentGainReduction = _getMeter(0);  // GR Left
  // New meters
  _currentInputLevel = _getMeter(2);     // Input Peak dB
  _currentOutputLevel = _getMeter(3);    // Output Peak dB
  _peakGainReduction = _getMeter(4);     // GR Max Hold
}
```

---

## UI LAYOUT

```
┌──────────────────────────────────────────────────────────────────┐
│  [Style ▼]  [Detection ▼]  [Character ▼]  [M/S]                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────── Transfer Curve ──────────┐  ┌───── GR Meter ──────┐ │
│   │         Knee vidljiv             │  │  L ████████████      │ │
│   │     . . . . . . . . .           │  │  R ████████████      │ │
│   │    /                            │  │  Hold: -8.1 dB       │ │
│   │   /                             │  │                      │ │
│   └──────────────────────────────────┘  └──────────────────────┘ │
│                                                                  │
│  [THRESH] [RATIO] [ATTACK] [RELEASE] [MAKEUP] [MIX]  [OUTPUT]  │
│   AUTO ↑                              AUTO ↑                    │
│                                                                  │
│  [KNEE] [RANGE] [DRIVE] [LOOKAHEAD] [ADAPTIVE]                  │
│                                                                  │
│  ── Sidechain ─────────────────────────────────────────────────  │
│  [HP ▸] [LP ◂] [EQ Mid] [Audition]                              │
│                                                                  │
│  ── Sync ──────────────────────────────────────────────────────  │
│  [Host Sync: OFF]  [♩ ♪ ♬ ♩. ♩₃]                               │
│                                                                  │
│  ── Meters ────────────────────────────────────────────────────  │
│  IN: -12.3 dB  │  OUT: -11.8 dB                                │
└──────────────────────────────────────────────────────────────────┘
```

---

## DEPENDENCY MAP

```
F1.1 (Knee) ──────────────────┐
F1.2 (Character+Drive) ───────┤
F1.3 (Range) ─────────────────┤
F1.4 (SC Filters) ────────────┤
F1.5 (Lookahead) ─────────────┤
F1.6 (Auto-Threshold) ────────┤──→ F2 (Wrapper 8→25) ──→ F3 (Tests) ──→ F4 (UI)
F1.7 (Auto-Makeup) ───────────┤
F1.8 (Detection Mode) ────────┤
F1.9 (Adaptive Release) ──────┤
F1.10 (Host Sync) ────────────┤
F1.11 (Mid/Side) ─────────────┤
F1.12 (Extended Meters) ──────┘
```

**Sve F1 taskove raditi PARALELNO (nezavisni).**
**F2 čeka sve F1. F3 čeka F2. F4 čeka F2.**

---

## SKIP LISTA

| Feature | Razlog |
|---------|--------|
| Latency Profiles (Live/Studio/Offline) | Lookahead ms ručno → PDC se sam rešava |
| SC EQ bands 4-6 | 1 mid band + HP/LP dovoljno (Pro-C 2 ima samo 4 total) |

---

## FILES LIST

### Rust (DSP + FFI)

| Fajl | Promene |
|------|---------|
| `crates/rf-dsp/src/dynamics.rs` | CharacterMode, SidechainFilter, LookaheadBuffer, Range, DetectionMode, AdaptiveRelease, HostSync, M/S |
| `crates/rf-engine/src/dsp_wrappers.rs` | CompressorWrapper: 8→25 params + 5 meters + get_param readback + latency |
| `crates/rf-dsp/tests/compressor_tests.rs` | NOVI — 38 unit + 8 integration tests |

### Flutter UI

| Fajl | Promene |
|------|---------|
| `flutter_ui/lib/widgets/fabfilter/fabfilter_compressor_panel.dart` | Wire 8-24, Style presets, Detection/M-S/Adaptive/Sync UI, Extended meters, A/B snapshot |

---

## TOTAL ESTIMATE

| Faza | LOC | Vreme |
|------|-----|-------|
| F1 (DSP Core) | ~800 | ~7h |
| F2 (Wrapper) | ~200 | ~2h |
| F3 (Tests) | ~800 | ~3h |
| F4 (UI + Styles) | ~500 | ~3h |
| **TOTAL** | **~2,300** | **~15-17h** |

---

*Last Updated: 2026-02-15 — Pro-C 2 class upgrade: 17 features, 8→25 params, 5 meters, Style Engine, Detection Modes, Adaptive Release, Host Sync, M/S, Extended Meters*
