# FF Compressor — Full Textual Specification

**Created:** 2026-02-15
**Status:** 📋 SPEC ONLY (no implementation started)
**Scope:** Complete spec za FluxForge Studio FF Compressor plugin

---

## 1. OVERVIEW

FF Compressor je profesionalni dynamics processor inspirisan FabFilter Pro-C 2.
Pokriva širok spektar kompresije — od transparentnog masterings do agresivnog FET pumpinga.

**Pozicija u sistemu:**
- InsertProcessor u DAW insert chain-u
- Dostupan u SVE TRI sekcije (DAW, Middleware, SlotLab)
- Koristi isti `insertSetParam()` / `insertGetParam()` FFI pipeline kao svi procesori

---

## 2. TRENUTNO STANJE

### 2.1 DSP Core (`crates/rf-dsp/src/dynamics.rs`)

| Aspekt | Vrednost |
|--------|---------|
| LOC | ~2,600 (ceo dynamics.rs) |
| Struct | `Compressor` (~300 bytes) |
| Stereo | `StereoCompressor` (~680 bytes) |
| Tipovi | 3 (VCA, Opto, FET) |
| Parametri | 7 u Compressor struct + 1 u StereoCompressor |
| Envelope | `EnvelopeFollower` sa SIMD (AVX2/AVX-512) |
| Lookup tablice | 2 (dB→linear 2048 entries, linear→dB 4096 entries) |
| Soft-knee | Da, parabolic interpolation |
| Sidechain | Da (mono + stereo) |
| Latencija | 0 samples (nema lookahead) |

### 2.2 Wrapper (`crates/rf-engine/src/dsp_wrappers.rs`)

| Aspekt | Vrednost |
|--------|---------|
| Struct | `CompressorWrapper` |
| Lokacija | Linije 840-962 |
| `num_params()` | 8 |
| Meteri | 2 (L/R gain reduction u dB) |

**Trenutni param indeksi:**

| Index | Ime | Raspon | Jedinica |
|-------|-----|--------|----------|
| 0 | Threshold | -60 do 0 | dB |
| 1 | Ratio | 1 do 100 | :1 |
| 2 | Attack | 0.01 do 500 | ms |
| 3 | Release | 1 do 5000 | ms |
| 4 | Makeup | -24 do +24 | dB |
| 5 | Mix | 0.0 do 1.0 | 0-1 |
| 6 | Link | 0.0 do 1.0 | 0-1 |
| 7 | Type | 0, 1, 2 | enum (VCA/Opto/FET) |

### 2.3 UI Panel (`flutter_ui/lib/widgets/fabfilter/fabfilter_compressor_panel.dart`)

| Aspekt | Vrednost |
|--------|---------|
| LOC | 1,508 |
| Layout | 3-kolona (Display 140px | Controls flex | Options 100px) |
| Header | 32px compact |
| Knobovi | 7 (Thresh, Ratio, Knee, Att, Rel, Mix, Out) svaki 48px |
| Stilovi | 14 (CompressionStyle enum) |
| Character | 4 (Off, Tube, Diode, Bright) |
| Sidechain | Toggle + HP/LP filteri |
| Painters | 3 (KneeCurve, LevelDisplay, SidechainEQ) |
| A/B | Da, CompressorSnapshot sa 14 polja |
| Metering | GR bar + transfer curve dot (30fps) |

---

## 3. ARHITEKTURA — TRI SLOJA

```
┌──────────────────────────────────────────────────────────┐
│  SLOJ 3: Flutter UI (fabfilter_compressor_panel.dart)     │
│  • 7 knobova (48px svaki)                                 │
│  • Transfer curve (KneeCurvePainter)                      │
│  • GR metering                                            │
│  • Style dropdown (14 stilova)                            │
│  • Character mode (Off/Tube/Diode/Bright)                │
│  • Sidechain EQ (HP/LP + 6 band)                         │
│  • A/B comparison                                         │
├──────────────────────────────────────────────────────────┤
│  SLOJ 2: Wrapper + FFI (dsp_wrappers.rs:840-962)         │
│  • CompressorWrapper : InsertProcessor                    │
│  • num_params() = 8                                       │
│  • set_param(index, value) / get_param(index)            │
│  • get_meter(0) = GR_L, get_meter(1) = GR_R             │
│  • process_stereo(&mut self, &mut [f64], &mut [f64])     │
├──────────────────────────────────────────────────────────┤
│  SLOJ 1: DSP Core (dynamics.rs)                           │
│  • Compressor struct (7 param + state)                    │
│  • StereoCompressor (L/R + link + sidechain)             │
│  • EnvelopeFollower (SIMD: AVX2/AVX-512)                 │
│  • 3 procesora: VCA, Opto, FET                           │
│  • Lookup tablice (dB↔linear, 6KB total)                 │
│  • Soft-knee (parabolic)                                  │
│  • Dry/wet mix (parallel compression)                     │
└──────────────────────────────────────────────────────────┘
```

---

## 4. DSP CORE — DETALJNA SPECIFIKACIJA

### 4.1 CompressorType Enum

```rust
pub enum CompressorType {
    Vca,   // Clean, transparent, fast — SSL, Neve, API
    Opto,  // Smooth, program-dependent — LA-2A, CL1B
    Fet,   // Aggressive, punchy, saturacija — 1176, Distressor
}
```

### 4.2 Compressor Struct

```rust
pub struct Compressor {
    // ═══ PARAMETRI ═══
    threshold_db: f64,      // -60 do 0 dB (default -20)
    ratio: f64,             // 1 do 100 (default 4.0)
    knee_db: f64,           // 0 do 24 dB (default 6.0)
    makeup_gain_db: f64,    // -24 do +24 dB (default 0.0)
    attack_ms: f64,         // 0.01 do 500 ms (default 10.0)
    release_ms: f64,        // 1 do 5000 ms (default 100.0)
    mix: f64,               // 0.0 do 1.0 (default 1.0)

    // ═══ TIP ═══
    comp_type: CompressorType,  // VCA/Opto/FET (default VCA)

    // ═══ STATE ═══
    envelope: EnvelopeFollower,
    gain_reduction: f64,
    opto_envelope: f64,
    opto_gain_history: [f64; 4],  // 4-tap smoothing
    fet_saturation: f64,
    sample_rate: f64,

    // ═══ SIDECHAIN ═══
    sidechain_enabled: bool,
    sidechain_key_sample: Sample,
}
```

### 4.3 Envelope Follower

```rust
pub struct EnvelopeFollower {
    attack_coeff: f64,    // Pre-calculated koeficijent
    release_coeff: f64,
    envelope: f64,        // Trenutna envelope vrednost
    sample_rate: f64,
}
```

**Algoritam (one-pole IIR):**
```rust
let coeff = if abs_input > self.envelope { attack_coeff } else { release_coeff };
self.envelope = abs_input + coeff * (self.envelope - abs_input);
```

**SIMD varijante:**
- `process_block_simd4()` — AVX2, 4-sample loop unrolling
- `process_block_simd8()` — AVX-512, 8-sample loop unrolling
- `process_block()` — auto-dispatch (feature detection)

### 4.4 VCA Processing

```
Input → Detection Signal → Envelope → dB Conversion → Gain Calc → Apply
```

**Karakteristike:**
- Direktan envelope following
- Brz, transparentan odziv
- Nema program-zavisnog ponašanja
- Koristi lookup tablice za dB/linear konverziju (~3-5x brže od exp/log)

### 4.5 Opto Processing

**Program-zavisni attack:**
```rust
let level_factor = (abs_detection * 10.0).min(1.0);
let effective_attack = attack_ms * (1.0 - level_factor * 0.5);
// Jači signal → brži attack (do 0.5x brži)
```

**Program-zavisni release:**
```rust
let release_factor = 1.0 + gain_reduction * 0.02;
let effective_release = release_ms * release_factor;
// Veća GR → sporiji release (2% po dB)
```

**4-tap history smoothing:**
```rust
opto_gain_history.rotate_right(1);
opto_gain_history[0] = gr_db;
let smoothed = opto_gain_history.iter().sum::<f64>() / 4.0;
```

### 4.6 FET Processing

**Dinamički ratio:**
```rust
let over = env_db - threshold_db;
let effective_ratio = ratio * (1.0 + over * 0.05).min(2.0);
// Jači signal → agresivniji ratio (do 2x)
```

**Soft-clip saturacija:**
```rust
let saturation_amount = (gr_db / 20.0).min(0.3);  // 0-30%
let x = saturated * (1.0 + saturation_amount);
output = x / (1.0 + x.abs() * saturation_amount * 0.5);
```

### 4.7 Soft-Knee Kalkulacija

```
                    ┌── hard compression: (input - thresh) * (1 - 1/ratio)
                    │
    knee_start ─────┤── parabolic blend: (slope * x²) / (2 * knee_db)
                    │
    knee_end ───────┘── no compression: 0.0

    knee_start = threshold - knee/2
    knee_end   = threshold + knee/2
```

### 4.8 Dry/Wet Mix (Parallel Compression)

```rust
let makeup = 10.0_f64.powf(makeup_gain_db / 20.0);
let wet = compressed * makeup;
output = dry * (1.0 - mix) + wet * mix;
```

| Mix | Rezultat |
|-----|----------|
| 0.0 | 100% dry — nema kompresije |
| 0.5 | 50/50 — NY-style parallel |
| 1.0 | 100% wet — puna kompresija |

### 4.9 StereoCompressor — Channel Linking

```rust
pub struct StereoCompressor {
    left: Compressor,
    right: Compressor,
    link: f64,  // 0.0 = independent, 1.0 = fully linked
    sidechain_enabled: bool,
    sidechain_key_left: Sample,
    sidechain_key_right: Sample,
}
```

**Link ponašanje:**

| Link | Ponašanje |
|------|-----------|
| 0.0 | Independent — svaki kanal zasebno |
| 0.01-0.99 | Parcijalni link — blend independent/linked |
| ≥0.99 | Fully linked — max(L,R) za envelope, ista GR na oba |

### 4.10 Lookup Tablice

| Tablica | Veličina | Raspon | Rezolucija |
|---------|----------|--------|------------|
| dB→linear | 2048 entries | -120 do +24 dB | Linearna interpolacija |
| linear→dB | 4096 entries | 1e-6 do 10.0 | Logaritmičko indeksiranje |

**Ukupno:** ~49 KB memorije
**Brzina:** ~3-5x brže od `exp()`/`log()` poziva

---

## 5. WRAPPER — FFI LAYER

### 5.1 CompressorWrapper

```rust
pub struct CompressorWrapper {
    comp: StereoCompressor,
    sample_rate: f64,
}

impl InsertProcessor for CompressorWrapper {
    fn num_params(&self) -> usize { 8 }
    fn process_stereo(&mut self, left: &mut [f64], right: &mut [f64]) { ... }
    fn set_param(&mut self, index: usize, value: f64) { ... }
    fn get_param(&self, index: usize) -> f64 { ... }
    fn get_meter(&self, index: usize) -> f64 { ... }
    fn param_name(&self, index: usize) -> &str { ... }
}
```

### 5.2 Param Index Tabela

| Index | Ime | Rust setter | Raspon | Default |
|-------|-----|-------------|--------|---------|
| 0 | Threshold | `set_threshold(dB)` | -60 do 0 dB | -20.0 |
| 1 | Ratio | `set_ratio(r)` | 1.0 do 100.0 | 4.0 |
| 2 | Attack | `set_attack(ms)` | 0.01 do 500 ms | 10.0 |
| 3 | Release | `set_release(ms)` | 1.0 do 5000 ms | 100.0 |
| 4 | Makeup | `set_makeup(dB)` | -24 do +24 dB | 0.0 |
| 5 | Mix | `set_mix(0-1)` | 0.0 do 1.0 | 1.0 |
| 6 | Link | `set_link(0-1)` | 0.0 do 1.0 | 1.0 |
| 7 | Type | `set_type(enum)` | 0/1/2 | 0 (VCA) |

### 5.3 Meter Index Tabela

| Index | Ime | Vrednost | Jedinica |
|-------|-----|---------|----------|
| 0 | GR Left | Gain reduction levog kanala | dB |
| 1 | GR Right | Gain reduction desnog kanala | dB |

### 5.4 FFI Flow

```
Flutter UI
    │
    ├─ insertSetParam(trackId, slotIndex, paramIndex, value)
    │   └─ CompressorWrapper.set_param(index, value)
    │       └─ StereoCompressor.set_both(|c| c.set_xxx(value))
    │
    ├─ insertGetParam(trackId, slotIndex, paramIndex) → f64
    │   └─ CompressorWrapper.get_param(index)
    │
    └─ insertGetMeter(trackId, slotIndex, meterIndex) → f64
        └─ CompressorWrapper.get_meter(index)
            └─ StereoCompressor.gain_reduction_db() → (f64, f64)
```

---

## 6. UI PANEL — DETALJNA SPECIFIKACIJA

### 6.1 Struktura (Trenutna)

```
FabFilterCompressorPanel [Column]
│
├── CompactHeader (32px)
│   ├── Ikona + "Compressor"
│   ├── Style Dropdown (14 stilova)
│   ├── A/B dugmad
│   └── Bypass dugme
│
└── Expanded [Row]
    │
    ├── LEFT: Transfer Curve Display (140px)
    │   ├── KneeCurvePainter
    │   │   ├── Grid (-60 do 0 dB, 12dB razmak)
    │   │   ├── 1:1 referentna linija
    │   │   ├── Compression kriva (narandžasta, 2.5px)
    │   │   ├── Threshold marker (narandžasta dashed)
    │   │   └── Input indicator (žuta tačka + crosshairs)
    │   │
    │   └── GR Meter (horizontalni bar)
    │       ├── Normalizovan na -40dB max
    │       ├── Orange→Red gradient
    │       └── Numerički prikaz (dB)
    │
    ├── CENTER: Control Knobs (flex 3)
    │   └── Row od 7 knobova (48px svaki)
    │       ├── THRESH  — narandžasta — (-60 do 0 dB)
    │       ├── RATIO   — narandžasta — (1:1 do 20:1)
    │       ├── KNEE    — plava       — (0 do 24 dB) ⚠️ UI-ONLY
    │       ├── ATT     — cyan        — (0.01 do 500 ms, log)
    │       ├── REL     — cyan        — (5 do 5000 ms, log)
    │       ├── MIX     — plava       — (0 do 100%)
    │       └── OUT     — zelena      — (-24 do +24 dB)
    │
    └── RIGHT: Options Panel (100px)
        ├── SC toggle
        ├── HP slider (20-500 Hz, log)
        ├── LP slider (1k-20k Hz, log)
        ├── CHARACTER dugmad (expert mode)
        │   ├── Off — siva
        │   ├── T (Tube) — narandžasta
        │   ├── D (Diode) — žuta
        │   └── B (Bright) — cyan
        └── Spacer
```

### 6.2 Knob Widget Spec

**Dijametar:** 48px (compact panel), 60px (default)
**Arc sweep:** 270° (135° do 405°, 7 o'clock do 5 o'clock)
**Value ring:** 4px stroke, zaobljeni krajevi

**Painted elementi:**
1. Modulation ring (opciono, žuta, 60% alpha, 3px)
2. Track (background, border boja, 4px)
3. Value arc (accent boja, 4px)
4. Knob body (circular, border koji se pojačava kad je aktivan)
5. Pointer (linija od centra do ivice, 2.5px)
6. Center dot (3px radijus)

**Interakcija:**
| Gest | Ponašanje | Osetljivost |
|------|-----------|-------------|
| Vertical drag | Menja vrednost | Normal: 0.005, Fine: 0.001 (Shift/Alt) |
| Scroll wheel | ±increment | Normal: ±0.02, Fine: ±0.005 (Shift) |
| Double-click | Reset na default | — |

### 6.3 Compression Styles (14)

| # | Stil | Label | Rust Type | Opis |
|---|------|-------|-----------|------|
| 1 | clean | Clean | VCA (0) | Transparentna digitalna kompresija |
| 2 | classic | Classic | VCA (0) | Klasični VCA stil |
| 3 | opto | Opto | Opto (1) | Optički kompresor emulacija |
| 4 | vocal | Vocal | Opto (1) | Optimizovan za vokale |
| 5 | mastering | Mastering | VCA (0) | Nežna mastering kompresija |
| 6 | bus | Bus | VCA (0) | Glue kompresija za buseve |
| 7 | punch | Punch | FET (2) | Punchy, čuva transijenте |
| 8 | pumping | Pumping | FET (2) | Namerni pumping efekat |
| 9 | versatile | Versatile | VCA (0) | Opšte namene |
| 10 | smooth | Smooth | Opto (1) | Super glatko lepljenje |
| 11 | upward | Upward | VCA (0) | Upward kompresija |
| 12 | ttm | TTM | FET (2) | To The Max — multiband |
| 13 | variMu | Vari-Mu | Opto (1) | Tube variable-mu |
| 14 | elOp | El-Op | Opto (1) | Optička emulacija |

**Mapiranje na Rust:** Svaki stil se mapira na jedan od 3 tipa (VCA=0, Opto=1, FET=2).
UI prikazuje 14 stilova, ali Rust procesor prima samo tip index (0/1/2).

### 6.4 Character Modes

| Mode | Label | Boja | Efekat |
|------|-------|------|--------|
| off | Off | Siva | Nema bojenja |
| tube | Tube | Narandžasta | Harmonička saturacija (parni harmonici) |
| diode | Diode | Žuta | Oštrija saturacija (neparni harmonici) |
| bright | Bright | Cyan | HF boost + blaga saturacija |

**Napomena:** Character modes su SAMO u UI — nemaju FFI param index u Rust-u.

### 6.5 Sidechain Sekcija

**Band struktura:**
```dart
class SidechainBand {
    int index;    // 0-5
    double freq;  // Hz (100, 200, 400, 800, 1600, 3200)
    double gain;  // dB
    double q;     // Q factor
    bool enabled;
}
```

**HP/LP filteri:**
| Filter | Min | Max | Skala |
|--------|-----|-----|-------|
| HPF | 20 Hz | 500 Hz | Logaritmička |
| LPF | 1000 Hz | 20000 Hz | Logaritmička |

### 6.6 A/B Comparison

**CompressorSnapshot čuva 14 vrednosti:**
```
threshold, ratio, knee, attack, release, range, mix, output,
style, character, drive, sidechainEnabled, sidechainHpf, sidechainLpf
```

**Dugmad:** A (20×20px), B (20×20px), Copy (18×18px)
**Interakcija:** Tap = switch, Long-press = store

### 6.7 Metering

| Meter | Izvor | Refresh rate |
|-------|-------|-------------|
| Gain Reduction | `insertGetMeter(track, slot, 0/1)` avg L+R | 30fps |
| Input Level | `getPeakMeters()` → dB konverzija | 30fps |
| Output Level | Deriviran (input + GR) | 30fps |
| Peak GR | Max tracker | Kontinualan |
| History buffer | 200 samples | Kad GR > 0.01 dB |

### 6.8 Custom Painters

| Painter | Namena | Canvas |
|---------|--------|--------|
| `_KneeCurvePainter` | Transfer curve sa knee | -60 do 0 dB (X=input, Y=output) |
| `_LevelDisplayPainter` | Scrolling level history | 200 samples, threshold linija |
| `_SidechainEqPainter` | Sidechain EQ response | 20 Hz do 20 kHz, log frekvencija |

---

## 7. POZNATI PROBLEMI I OGRANIČENJA

### 7.1 Knee je UI-Only

`knee_db` parametar postoji u Compressor struct-u, ali CompressorWrapper ga NE eksponira.
Transfer curve ga vizualizuje, ali Rust procesor ga NE prima preko `set_param()`.

**Status:** UI-only feature. Knee se kalkuliše lokalno za prikaz krive.

### 7.2 Character Modes Nemaju FFI

4 character mode-a (Off, Tube, Diode, Bright) su SAMO u UI.
Rust DSP core ih ne implementira — nema param index-a za njih.

### 7.3 Sidechain EQ Nije Povezan

`SidechainBand` struktura (6 bendova) postoji u UI state-u, ali:
- Nema FFI binding-a za sidechain EQ
- `_SidechainEqPainter` crta, ali ne utiče na audio
- HP/LP filteri su takođe samo u UI

### 7.4 Nema Lookahead-a

Trenutni kompresor nema lookahead mehanizam:
- Envelope reaguje TEK NAKON što signal premaši threshold
- Za brz attack, ovo može propustiti transijenте
- Pro-C 2 ima optional lookahead od 0-20ms

### 7.5 Auto-Threshold Nije Implementiran

`_autoThreshold` state varijabla postoji (linija 226) ali nije povezana.

### 7.6 Host Sync Nije Implementiran

`_hostSync` state varijabla postoji (linija 233) ali nije povezana.

### 7.7 Range Parametar Nije u FFI

`_range` (opseg GR, -40 do 0 dB) postoji u UI ali nema param index u Rust-u.

### 7.8 Drive Parametar Nije u FFI

`_drive` (0 do 24 dB) postoji u UI ali nema param index u Rust-u.

---

## 8. PERFORMANCE KARAKTERISTIKE

| Metrika | Vrednost |
|---------|---------|
| Per-sample CPU (stereo) | ~50-100 ciklusa (sa SIMD dispatch) |
| Lookup tablica memorija | 49 KB (2048 + 4096 entries) |
| Compressor struct | ~300 bytes |
| StereoCompressor | ~680 bytes |
| Latencija | 0 samples (instant) |
| Heap alokacije u process() | 0 (lock-free) |
| SIMD dispatch | Runtime AVX-512 → AVX2 → scalar |

---

## 9. TESTOVI (Trenutni)

| Test | Opis |
|------|------|
| `test_compressor_types()` | VCA/Opto/FET svi proizvode GR |
| `test_stereo_compressor_link()` | Linked kompresor daje isti GR na oba kanala |
| `test_compressor_sidechain()` | Eksterni sidechain detekcija radi |
| `test_stereo_compressor_sidechain()` | Stereo sidechain detekcija |
| `test_envelope_simd_vs_scalar()` | SIMD loop-unrolled = scalar |
| `test_envelope_simd_performance()` | 8192-sample block processing |
| `test_envelope_avx512()` | AVX-512 (8-sample) processing |
| `test_db_to_linear_lookup()` | Lookup tačnost < 0.01 error |
| `test_linear_to_db_lookup()` | Inverzni lookup < 0.5 dB error |
| `test_lookup_vs_precise()` | Lookup vs exp()/log() |
| `test_compressor_gain_fast()` | Gain formula verifikacija |

---

## 10. COMPLETE FILE LIST

### Rust DSP

| Fajl | LOC | Opis |
|------|-----|------|
| `crates/rf-dsp/src/dynamics.rs` | ~2,600 | Compressor, Limiter, Gate, Expander, EnvelopeFollower, lookup tablice |
| `crates/rf-engine/src/dsp_wrappers.rs` | ~130 (comp sekcija) | CompressorWrapper : InsertProcessor |

### Flutter UI

| Fajl | LOC | Opis |
|------|-----|------|
| `flutter_ui/lib/widgets/fabfilter/fabfilter_compressor_panel.dart` | 1,508 | Kompletna UI |
| `flutter_ui/lib/widgets/fabfilter/fabfilter_panel_base.dart` | 732 | Bazna klasa (A/B, bypass, expert) |
| `flutter_ui/lib/widgets/fabfilter/fabfilter_knob.dart` | 354 | Knob widget |
| `flutter_ui/lib/widgets/fabfilter/fabfilter_theme.dart` | ~200 | Boje i stilovi |

---

## 11. ENUM → RUST TYPE MAPPING TABELA

```
UI Style       →  Rust CompressorType  →  FFI param 7 value
─────────────────────────────────────────────────────────────
clean          →  Vca                  →  0.0
classic        →  Vca                  →  0.0
opto           →  Opto                 →  1.0
vocal          →  Opto                 →  1.0
mastering      →  Vca                  →  0.0
bus            →  Vca                  →  0.0
punch          →  Fet                  →  2.0
pumping        →  Fet                  →  2.0
versatile      →  Vca                  →  0.0
smooth         →  Opto                 →  1.0
upward         →  Vca                  →  0.0
ttm            →  Fet                  →  2.0
variMu         →  Opto                 →  1.0
elOp           →  Opto                 →  1.0
```

---

## 12. DEAD FEATURE SUMMARY

Sledeće feature-i postoje u UI ali NEMAJU DSP backend:

| Feature | UI State | FFI Index | Status |
|---------|----------|-----------|--------|
| Knee | `_knee` (0-24 dB) | ❌ Nema | UI-only za transfer curve |
| Character | `_character` (enum) | ❌ Nema | Off/Tube/Diode/Bright bez DSP |
| Drive | `_drive` (0-24 dB) | ❌ Nema | Nema saturacije u Rust-u |
| Range | `_range` (-40-0 dB) | ❌ Nema | Nema GR range limita u Rust-u |
| SC EQ bands | 6 bendova | ❌ Nema | Nema sidechain filtera u Rust-u |
| SC HP/LP | Hz sliders | ❌ Nema | Nema sidechain filtera u Rust-u |
| SC Audition | bool toggle | ❌ Nema | Nema SC listen u Rust-u |
| Auto-Threshold | bool flag | ❌ Nema | Nema auto-thresh kalkulacije |
| Host Sync | bool flag | ❌ Nema | Nema transport sync-a |
| Lookahead | — | ❌ Nema | Nema lookahead buffer-a |

**Ukupno: 10 dead features** — postoje u UI ali ne utiču na audio.
