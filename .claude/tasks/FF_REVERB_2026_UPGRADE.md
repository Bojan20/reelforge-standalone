# FF Reverb 2026 — FDN Core Redesign

**Created:** 2026-02-15
**Status:** 🔴 NOT STARTED
**Estimated:** ~16-18h across 4 faza
**Risk:** LOW (zero breaking FFI signatures, internal algorithm swap)

---

## CILJ

Zamena Freeverb-core (1996) sa 2026-grade FDN reverb-om.
Zadržavamo InsertProcessor integraciju, wrapper, FFI pipeline.
Proširujemo sa 8 na 15 parametara (12 core + Thickness, Ducking, Freeze).

---

## NON-NEGOTIABLE

- Deterministic processing (fixed seed za modulation)
- Zero heap allocation u `process()`
- SIMD-safe memory alignment
- Backward-compatible FFI (prvih 8 indeksa kompatibilni)
- Zero breaking changes u ReverbWrapper trait impl

---

## FAZA 1 — RUST DSP CORE (~6h)

### F1.1: Brisanje Freeverb jezgra ✅→⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs`

**Obrisati:**
- `CombFilter` struct + impl (8 instanci)
- `AllpassFilter` struct + impl (4 instanci)
- Fiksna comb feedback formula (`0.28 + room_size * 0.7`)
- 23-sample stereo offset model
- Cross-feed width blending formula
- `set_type()` override logika (gde Type prepisuje room_size/damping)

**Zadržati:**
- `AlgorithmicReverb` struct (samo menja internals)
- Pre-delay circular buffer (L/R)
- `ConvolutionReverb` (potpuno nepromenjen)
- `ReverbType` enum (Room, Hall, Plate, Chamber, Spring)
- Svi public method signatures

---

### F1.2: EarlyReflectionEngine ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs` (novi struct)

```rust
struct EarlyReflectionEngine {
    taps: [DelayTap; 8],    // 8 tapova (ne 12 — dovoljno za slot audio)
    buffer_l: Vec<f64>,
    buffer_r: Vec<f64>,
    write_pos: usize,
    density: f64,           // 0.0-1.0
    distance: f64,          // 0.0-1.0
}

struct DelayTap {
    delay_samples: usize,   // Prime offsets, precomputed
    gain: f64,              // Fixed seed, no runtime random
    lpf_coeff: f64,         // Distance-dependent LP
    lpf_state: f64,
}
```

**Ponašanje:**
- 8 non-linear spaced tapova (prime offsets)
- Distance kontroliše: ER gain, LP filtering, density scaling
- Svi tap offsets precomputed u `new()` — nema runtime random
- Fixed seed za determinizam

**Tapovi (prime, ms @ 48kHz):**
```
[7, 11, 17, 23, 31, 41, 53, 67] ms
= [336, 528, 816, 1104, 1488, 1968, 2544, 3216] samples
```

---

### F1.3: DiffusionStage ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs` (novi struct)

```rust
struct DiffusionStage {
    allpasses: [AllpassFilter; 6],  // 6 umesto 4
    active_count: usize,            // Controlled by diffusion param
}
```

**Ponašanje:**
- 6 serial allpass filtera (zamenjuje stara 4)
- Feedback range: 0.4–0.75 (kontrolisano diffusion parametrom)
- `diffusion` param kontroliše:
  - `active_count`: 2-6 (manje = sušlji, više = gušći)
  - feedback coefficient unutar range-a
- Allpass delay lengths (prime): `[113, 157, 211, 269, 337, 409]` samples

---

### F1.4: FDNCore 8×8 ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs` (novi struct, SRCE upgradeа)

```rust
struct FDNCore {
    delay_lines: [FDNDelayLine; 8],
    matrix: [[f64; 8]; 8],          // Hadamard feedback matrix
    feedback_gains: [f64; 8],        // Per-line gain
    lfo_phases: [f64; 8],           // Multi-phase modulation
    lfo_increment: f64,              // Fixed, deterministic
    mod_depth: f64,                  // 0.001-0.003 (0.1-0.3%)
}

struct FDNDelayLine {
    buffer: Vec<f64>,
    write_pos: usize,
    base_delay: usize,              // Prime-distributed
    current_delay: f64,             // Modulated (fractional)
    damping_lpf: f64,              // Low decay multiplier
    damping_hpf: f64,              // High decay multiplier
    damping_state: f64,
}
```

**Delay lengths (prime-distributed, samples @ 48kHz):**
```
[1087, 1283, 1481, 1669, 1877, 2083, 2293, 2503]
```

**Hadamard 8×8 matrica:**
```
H₈ = (1/√8) × Hadamard(8)
```
Svaki element je `±1/√8 ≈ ±0.3536`

**LFO Modulation:**
- 8 faza, ravnomerno raspoređene: `phase[i] = i * π/4`
- Depth: 0.1-0.3% delay length
- Increment: fiksiran na ~0.3 Hz (sprečava metallic ringing)
- Seed: fiksiran (determinism)

**Feedback gains:**
- `decay` param (0.0-1.0) → `gain = 0.85 + decay * 0.14` (range 0.85-0.99)
- Eigenvalues matrice UVEK ≤ 0.99 (stabilnost)

---

### F1.5: MultiBandDecayShaper ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs` (novi struct)

```rust
struct MultiBandDecayShaper {
    low_crossover: f64,     // 250 Hz
    high_crossover: f64,    // 4000 Hz
    low_mult: f64,          // 0.5-2.0
    high_mult: f64,         // 0.5-2.0
}
```

**Ponašanje:**
- 3-band: Low (<250Hz), Mid (250-4kHz), High (>4kHz)
- Primenjuje se UNUTAR FDN feedback path-a (NE post-EQ)
- Formula: `bandDecay = globalDecay × bandMultiplier`
- Low mult > 1.0 = duži bass decay (hall character)
- High mult < 1.0 = kraći treble decay (natural absorption)

**Implementacija:** Dva one-pole filtera (LP + HP) za band splitting unutar svake FDN delay linije.

---

### F1.6: MidSide Width ⬜

**Zamenjuje** stari cross-feed model.

```rust
fn apply_width(&self, left: f64, right: f64) -> (f64, f64) {
    let mid = (left + right) * 0.5;
    let side = (left - right) * 0.5;
    let side_scaled = side * self.width;  // 0.0-2.0
    (mid + side_scaled, mid - side_scaled)
}
```

- Width 0.0 = mono
- Width 1.0 = natural stereo
- Width 2.0 = ultra-wide (200%)

---

### F1.7: Parameter System Expansion (8→15) ⬜

**Novi layout:**

| Index | Param | Range | Default | Zamenjuje |
|-------|-------|-------|---------|-----------|
| 0 | Space | 0.0-1.0 | 0.5 | Room Size |
| 1 | Brightness | 0.0-1.0 | 0.6 | Damping (invertovano) |
| 2 | Width | 0.0-2.0 | 1.0 | Width (prošireno) |
| 3 | Mix | 0.0-1.0 | 0.33 | Dry/Wet |
| 4 | PreDelay | 0.0-500.0 | 0.0 | PreDelay (ms, prošireno) |
| 5 | Style | 0-4 (int) | 0 | Type |
| 6 | Diffusion | 0.0-1.0 | 0.7 | Diffusion |
| 7 | Distance | 0.0-1.0 | 0.5 | Distance |
| 8 | **Decay** | 0.0-1.0 | 0.5 | **NOVO** |
| 9 | **LowDecayMult** | 0.5-2.0 | 1.0 | **NOVO** |
| 10 | **HighDecayMult** | 0.5-2.0 | 1.0 | **NOVO** |
| 11 | **Character** | 0.0-1.0 | 0.3 | **NOVO** |
| 12 | **Thickness** | 0.0-1.0 | 0.3 | **NOVO** (delay spread + low boost) |
| 13 | **Ducking** | 0.0-1.0 | 0.0 | **NOVO** (self-duck amount) |
| 14 | **Freeze** | 0.0/1.0 | 0.0 | **NOVO** (bool, momentary) |

**Parameter mapping:**

- **Space:** Skalira FDN delay lengths + ER spacing
- **Brightness:** Mapira na HF decay multiplier (1.0=bright, 0.0=dark)
- **Style:** Bira topology preset (scaling factors, NE direktan override)
- **Decay:** Globalni decay scalar (feedback gains)
- **LowDecayMult:** MultiBandDecayShaper low band
- **HighDecayMult:** MultiBandDecayShaper high band
- **Character:** Mapira na mod depth + diffusion density + ER prominence

**Style presets (NE override, samo scaling factors):**

| Style | Space Scale | ER Scale | Diffusion Scale | Mod Scale |
|-------|------------|----------|-----------------|-----------|
| Room | 0.6 | 0.8 | 0.7 | 0.5 |
| Hall | 1.2 | 1.0 | 0.9 | 0.8 |
| Plate | 0.8 | 0.3 | 1.0 | 1.0 |
| Chamber | 0.7 | 0.9 | 0.8 | 0.6 |
| Spring | 0.5 | 0.5 | 0.6 | 1.2 |

---

### F1.8: Signal Flow (kompletno) ⬜

```
Input
  → PreDelay (0-500ms circular buffer)
  → EarlyReflectionEngine (8 taps, distance-controlled)
  → DiffusionStage (6 serial allpass, diffusion-controlled)
  → FDNCore 8×8 (Hadamard, modulated, multi-band decay)
  → MidSideWidth (0-200%)
  → Equal-power Wet/Dry crossfade
  → Output
```

---

### F1.9: Thickness + Ducking + Freeze (3 nova parametra) ⬜

**Odluka:** Implementiramo 3 od 4 UI knoba. Gate se SKIP-uje (koristi Gate processor iz insert chain-a).

#### Thickness (param index 12)

**Fajl:** `crates/rf-dsp/src/reverb.rs` (mod u FDNCore)

```rust
// Unutar FDNCore
thickness: f64,  // 0.0-1.0, default 0.3

fn apply_thickness(&mut self) {
    // 1. Modulate delay spread: manje = gušći zvuk
    let spread_factor = 1.0 - self.thickness * 0.5;  // 1.0→0.5
    // 2. Low-shelf boost inside feedback: +0 do +6dB @ 200Hz
    let low_boost_db = self.thickness * 6.0;
}
```

**Ponašanje:**
- Thickness 0.0 = normalan spacing, bez low boost
- Thickness 0.5 = blago gušći, +3dB low shelf
- Thickness 1.0 = maksimalno gust, delay lines blizu, +6dB low shelf
- ~30 LOC

#### Ducking — Self-Duck (param index 13)

**Fajl:** `crates/rf-dsp/src/reverb.rs` (novi struct)

```rust
struct SelfDucker {
    envelope: f64,           // 0.0-1.0 tracked envelope
    attack_coeff: f64,       // ~5ms attack
    release_coeff: f64,      // ~200ms release
    amount: f64,             // 0.0-1.0 duck amount
}

impl SelfDucker {
    fn process(&mut self, dry_level: f64, wet: &mut f64) {
        // Track DRY signal envelope
        let abs_dry = dry_level.abs();
        if abs_dry > self.envelope {
            self.envelope += (abs_dry - self.envelope) * self.attack_coeff;
        } else {
            self.envelope += (abs_dry - self.envelope) * self.release_coeff;
        }
        // Duck WET signal: louder dry = quieter wet
        let duck_gain = 1.0 - self.envelope * self.amount;
        *wet *= duck_gain.max(0.0);
    }
}
```

**Ponašanje:**
- Self-ducking: koristi DRY signal kao sidechain izvor
- Amount 0.0 = nema ducking-a
- Amount 0.5 = blagi duck tokom glasnog inputa
- Amount 1.0 = potpuni duck — reverb se čuje samo u tišini
- **NE menja InsertProcessor trait** — koristi interni DRY buffer
- ~80 LOC

#### Freeze (param index 14)

**Fajl:** `crates/rf-dsp/src/reverb.rs` (mod u FDNCore)

```rust
// Unutar FDNCore
freeze: bool,  // false default

fn apply_freeze(&self, feedback: f64, input_gain: f64) -> (f64, f64) {
    if self.freeze {
        (0.999, 0.0)  // Max feedback, zero input → infinite sustain
    } else {
        (feedback, input_gain)
    }
}
```

**Ponašanje:**
- Freeze OFF (0.0) = normalan rad
- Freeze ON (1.0) = feedback → 0.999, input → 0.0
- FDN stanje se zamrzava — beskonačni tail
- UI: momentary button (press/release), NE toggle knob
- ~15 LOC

---

## FAZA 2 — WRAPPER + FFI (~2h)

### F2.1: ReverbWrapper update ⬜

**Fajl:** `crates/rf-engine/src/dsp_wrappers.rs` (linije 1529-1750)

```rust
impl InsertProcessor for ReverbWrapper {
    fn param_count(&self) -> usize { 15 }  // Bilo 8

    fn set_param(&mut self, idx: usize, val: f64) {
        match idx {
            0 => self.reverb.set_space(val),
            1 => self.reverb.set_brightness(val),
            2 => self.reverb.set_width(val),
            3 => self.reverb.set_mix(val),
            4 => self.reverb.set_predelay(val),
            5 => self.reverb.set_style(ReverbType::from(val as u32)),
            6 => self.reverb.set_diffusion(val),
            7 => self.reverb.set_distance(val),
            8 => self.reverb.set_decay(val),
            9 => self.reverb.set_low_decay_mult(val),
            10 => self.reverb.set_high_decay_mult(val),
            11 => self.reverb.set_character(val),
            12 => self.reverb.set_thickness(val),
            13 => self.reverb.set_ducking(val),
            14 => self.reverb.set_freeze(val > 0.5),
            _ => {}
        }
    }

    fn get_param(&self, idx: usize) -> f64 {
        match idx {
            0 => self.reverb.space(),
            1 => self.reverb.brightness(),
            2 => self.reverb.width(),
            3 => self.reverb.mix(),
            4 => self.reverb.predelay_ms(),
            5 => self.reverb.style() as f64,
            6 => self.reverb.diffusion(),
            7 => self.reverb.distance(),
            8 => self.reverb.decay(),
            9 => self.reverb.low_decay_mult(),
            10 => self.reverb.high_decay_mult(),
            11 => self.reverb.character(),
            12 => self.reverb.thickness(),
            13 => self.reverb.ducking(),
            14 => if self.reverb.freeze() { 1.0 } else { 0.0 },
            _ => 0.0,
        }
    }
}
```

**Backward compatibility:**
- Indeksi 0-7 mapiraju na iste semantičke parametre
- Stari `set_room_size()` → novi `set_space()`
- Stari `set_damping()` → novi `set_brightness()` (invertovano)
- Stari `set_type()` → novi `set_style()` (bez override)
- Indeksi 8-14 su novi — stari kod ih ne poziva, nema breakage

---

### F2.2: Rename public API methods ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs`

| Stari | Novi | Napomena |
|-------|------|---------|
| `set_room_size()` | `set_space()` | Semantički jasniji |
| `room_size()` | `space()` | Getter |
| `set_damping()` | `set_brightness()` | Invertovano (bright=1 znači damping=0) |
| `damping()` | `brightness()` | Getter |
| `set_dry_wet()` | `set_mix()` | Kraći |
| `dry_wet()` | `mix()` | Getter |
| `set_type()` | `set_style()` | Bez override ponašanja |
| `reverb_type()` | `style()` | Getter |
| — | `set_decay()` | **NOVO** |
| — | `decay()` | **NOVO** getter |
| — | `set_low_decay_mult()` | **NOVO** |
| — | `low_decay_mult()` | **NOVO** getter |
| — | `set_high_decay_mult()` | **NOVO** |
| — | `high_decay_mult()` | **NOVO** getter |
| — | `set_character()` | **NOVO** |
| — | `character()` | **NOVO** getter |
| — | `set_thickness()` | **NOVO** (delay spread + low boost) |
| — | `thickness()` | **NOVO** getter |
| — | `set_ducking()` | **NOVO** (self-duck amount) |
| — | `ducking()` | **NOVO** getter |
| — | `set_freeze(bool)` | **NOVO** (momentary freeze) |
| — | `freeze()` | **NOVO** getter (bool) |

---

## FAZA 3 — TESTOVI (~4h)

### F3.1: Unit testovi za FDN core ⬜

**Fajl:** `crates/rf-dsp/src/reverb.rs` (tests mod)

| Test | Opis |
|------|------|
| `test_fdn_impulse_response` | Impuls → decay, no NaN/Inf |
| `test_fdn_silence_after_decay` | Silence input → output decays to 0 |
| `test_fdn_parameter_sweep` | 15 params × 3 values × 5 styles = 225 cases |
| `test_fdn_determinism` | Isti input + isti params = bit-exact output |
| `test_fdn_stability` | 10s sustained input, output stays bounded |
| `test_fdn_style_no_override` | Style change NE menja Space/Brightness |
| `test_fdn_width_mono` | Width=0 → L==R |
| `test_fdn_width_wide` | Width=2.0 → enhanced stereo |
| `test_fdn_multiband_decay` | Low mult=2.0 → bass decays slower |
| `test_fdn_character` | Character=1.0 → denser tail |
| `test_fdn_early_reflections` | Distance=0 → strong ER, Distance=1 → weak ER |
| `test_fdn_predelay` | Pre-delay adds exact sample offset |
| `test_fdn_thickness` | Thickness=1.0 → denser, more low-end |
| `test_fdn_ducking` | Loud input → wet signal attenuated |
| `test_fdn_ducking_release` | After input stops, wet recovers |
| `test_fdn_freeze_on` | Freeze=true → infinite sustain, no new input |
| `test_fdn_freeze_off` | Freeze=false → normal operation |

**Minimalno 25 testova.**

---

### F3.2: Integration testovi ⬜

**Fajl:** `crates/rf-engine/tests/` (novi fajl)

| Test | Opis |
|------|------|
| `test_reverb_wrapper_param_count` | `param_count() == 15` |
| `test_reverb_wrapper_roundtrip` | `set_param(i, v)` → `get_param(i) == v` za svih 15 |
| `test_reverb_wrapper_process` | Wrapper process ne panick-uje |
| `test_reverb_factory` | `create_processor_extended("reverb")` vraća FDN |

---

### F3.3: A/B regression ⬜

- Snimiti output starog Freeverb-a (5 testnih signala × 5 style-ova = 25 .wav)
- Snimiti output novog FDN-a sa istim parametrima
- Subjektivno: FDN MORA zvučati bolje ili jednako (nikad gore)
- Objektivno: Decay time razlika ≤ 20% za iste parametre

---

## FAZA 4 — UI (Pro-R 2 Class Panel Rewrite) ⬜

**Kompletna vizuelna specifikacija dobijena od korisnika.**

### F4.0: Cilj utiska

Mastering-grade plugin izgled: miran, tehnički, skup, precizan.
Nema "gaming" estetike, nema teških senki, nema šarenila.

---

### F4.1: Panel veličine i responsivnost ⬜

**3 standardne veličine:**

| Veličina | Dimenzije | Inspector |
|----------|-----------|-----------|
| S (Compact) | 960 × 560 | Collapsed u bottom drawer |
| M (Default) | 1180 × 680 | 240px desno |
| L (Large) | 1440 × 820 | 300px desno |

**Responsivna pravila:**
- ≥1200px: Inspector stalno vidljiv (300px)
- 900-1199px: Inspector 240px
- <900px: Inspector u bottom drawer (ispod display-a, ne preklapa)
- <750px: Knobovi u 3 kolone (umesto 6), i dalje 2 macro reda

---

### F4.2: Vertikalne zone (3 zone) ⬜

```
┌─────────────────────────────────────────────────┐
│ ZONA A — Header (48px fiksno)                    │
│ baseBg, 1px hairline dole (white 6-8% opacity)  │
├─────────────────────────────────────────────────┤
│ ZONA B — Macro Controls (170px, clamp 150-190)   │
│ panelBg, radius 20px, padding 16px              │
│ Row 1: Space, Decay, Style, PreDelay, Width, Mix│
│ Row 2: Character, Brightness, Distance,         │
│        Thickness, Ducking + Freeze button       │
├─────────────────────────────────────────────────┤
│ ZONA C — Display Area (sav preostali prostor)    │
│ gradient top→bottom, radius 20px, padding 16px  │
│ Decay EQ + Post EQ curves + Analyzer + Bands    │
└─────────────────────────────────────────────────┘
```

---

### F4.3: Color System (mastering dark) ⬜

**Background slojevi:**
| Token | Hex | Namena |
|-------|-----|--------|
| baseBg | #0F1115 | Najdublji sloj |
| panelBg | #161A21 | Surface panela |
| hoverBg | #1C212A | Hover state |

**Grid / hairlines:**
| Token | Vrednost |
|-------|----------|
| gridMajor | #2A2F3A @ 18% |
| gridMinor | #2A2F3A @ 10% |
| hairline | white @ 6-8%, uvek 1px |

**Tekst:**
| Token | Hex |
|-------|-----|
| primary | #E8ECF3 |
| secondary | #9AA4B2 |
| disabled | #5B6472 |

**Akcenti:**
| Token | Hex | Namena |
|-------|-----|--------|
| decayAccent | #00E0FF | Decay EQ kriva (cyan neon) |
| postAccent | #A06BFF | Post EQ kriva (soft purple) |
| analyzerGradient | #00E0FF → #0044FF | Spektar |

**Font:** Inter (fallback SF Pro)
- Title: 14px Medium
- Label: 11px Medium, ALL CAPS, tracking +0.8
- Value: 12px Regular, tabular numbers

---

### F4.4: Header (Zona A, 48px) ⬜

**Levo:**
- `FF REVERB` (caps, 12-13px, medium)
- Ispod (opciono): `Algorithmic / 2026` (10px secondary)

**Centar:**
- Preset dropdown (capsule: 26px visina, panelBg fill, hairline border)
- A/B toggle (segmented pill, active = 14% accent tint)

**Desno:**
- Undo/Redo ikone (18px)
- Bypass LED (10px krug, ON=crvena+glow, OFF=siva)
- Output meter placeholder (4px vertical bar, accent gradient)

**Motion:** Hover 150-180ms opacity fade. Bez bounce/spring.

---

### F4.5: Macro Controls (Zona B, 170px) ⬜

**Row 1 (6 elemenata):**

| # | Kontrola | Tip | Param Index |
|---|----------|-----|-------------|
| 1 | Space | Knob | 0 |
| 2 | Decay | Knob | 8 |
| 3 | Style | Segmented selector | 5 |
| 4 | PreDelay | Knob | 4 |
| 5 | Width | Knob | 2 |
| 6 | Mix | Knob | 3 |

**Row 2 (5 knobova + Freeze button):**

| # | Kontrola | Tip | Param Index |
|---|----------|-----|-------------|
| 1 | Character | Knob | 11 |
| 2 | Brightness | Knob | 1 |
| 3 | Distance | Knob | 7 |
| 4 | Thickness | Knob | 12 |
| 5 | Ducking | Knob | 13 |
| 6 | Freeze | Button (desno poravnat) | 14 |

**Razmak:** 18-22px između elemenata.

---

### F4.6: Knob vizuelni dizajn ⬜

**Dimenzije:**
- Prečnik: 72px (M), 64px (S), 78px (L)
- Arc sweep: 300° (gap dole)
- Background ring: 2px, 18% opacity
- Value ring: 5px, accent color, blag glow

**Unutrašnjost:**
- Centralni value tekst (12px, tabular)
- Unit ispod (10px secondary): %, ms, x
- Label ispod knob-a: 11px ALL CAPS, secondary, 8px gap

**States:**
- Idle: ring slab
- Hover: +10% opacity + blag glow
- Active: glow 60%, ring jači

**Tooltip:** Floating capsule iznad knob-a (baseBg 90%, border 1px accent 40%, text primary 12px)

---

### F4.7: Style selector ⬜

Segmented pill: 5 segmenata (Room/Hall/Plate/Chamber/Spring)
- Visina 32px, radius 16px
- Inactive: transparent, hairline outline, text secondary
- Active: fill 14% accent tint, text primary
- Hover: background tint 10%

---

### F4.8: Freeze dugme ⬜

Capsule dugme:
- Visina 32px, radius 16px, outline hairline
- Ikonica snowflake + label `FREEZE` (caps)
- Active: fill 12% accent tint, minimalan glow
- Momentary (press/release), NE toggle

---

### F4.9: Display zona (Zona C) ⬜

**Pozadina:**
- Gradient: top #0F1115 → bottom #121623
- Suptilan vignette (tamni rubovi)
- Noise overlay 2% opacity (opciono)

**Grid X osa (log freq):**
- Major vertikale: 20, 50, 100, 200, 500, 1k, 2k, 5k, 10k, 20k
- Minor linije između, 50% tanje

**Grid Y ose:**
- Decay EQ mod: 25% – 400%
- Post EQ mod: -24dB – +24dB
- Labels: 10px secondary, samo major tickovi

**Analyzer:**
- Linija 2px
- Glow ispod: 8px blur @ 18% opacity
- Boja: cyan→blue gradient
- Stabilan smoothing (bez flickera)

**Curves (obe uvek vidljive):**
- Decay EQ: stroke 2.5px, decayAccent, glow 6px blur @ 20%
- Post EQ: stroke 2.0px, postAccent, glow 5px blur @ 14%
- Inactive curve: alpha 40%

**Band dots:**
- Radius 6-7px, filled accent, outline 1px white @ 45%
- Selected: outer ring 2px accent, halo glow 12px blur @ 22%, breathing pulse 2.2s 8% scale
- Hover: scale 1.08, outline jači

**Rectangle selection:**
- Fill: decayAccent @ 10%, border dashed 1px accent @ 40%, radius 6px, fade-out 120ms

---

### F4.10: Bottom-left toggles ⬜

3 capsule dugmeta (24px visina):
- `DECAY EQ` | `POST EQ` | `PIANO`
- Active: fill 12% accent tint, text primary
- Inactive: outline hairline, text secondary

---

### F4.11: Piano strip ⬜

- Visina: 52px, na dnu display-a
- White keys: #E9EDF5 @ 92%
- Black keys: #2B313C
- Separators: 1px dark lines
- Band dots prikazani i na pianu istim stilom

---

### F4.12: Inspector panel ⬜

**Širina:** 300px (L), 240px (M), collapsed (S)
**Pozadina:** panelBg, leva border hairline

**Header:**
- `BAND` (caps 11px secondary)
- Mode toggle (Decay/Post) mini

**Sekcije:**
| Sekcija | Kontrola |
|---------|----------|
| Frequency | Input box (34px, baseBg, hairline) |
| Amount | Input box |
| Q | Input box |
| Type | Dropdown |

**Dugmad dole:** Reset / Copy / Paste (flat outline, 30px visina)

---

### F4.13: Motion princip ⬜

- Sve tranzicije: easeOutCubic, 120-180ms
- Bez bounce/spring
- Bez agresivnih animacija

---

### F4.14: Zabranjeno (vizuelno) ⬜

- RGB šarenilo
- Teški drop shadows
- Skeuomorphic metal
- Previše teksta
- Grube linije / aliasing
- Cartoon ikonice

---

### F4.15: Fajlovi za UI ⬜

| Fajl | Tip | LOC estimate |
|------|-----|--------------|
| `fabfilter_reverb_panel.dart` | **REWRITE** | ~1400 LOC |
| `internal_processor_editor_window.dart` | UPDATE (15 params) | +50 LOC |

---

## FAJLOVI KOJI SE MENJAJU

| Fajl | Tip promene | LOC estimate |
|------|------------|--------------|
| `crates/rf-dsp/src/reverb.rs` | **MAJOR** — novi FDN core | +400, -200 |
| `crates/rf-engine/src/dsp_wrappers.rs` | UPDATE — 15 params | +40, -15 |
| `flutter_ui/lib/widgets/fabfilter/fabfilter_reverb_panel.dart` | **REWRITE** — Pro-R 2 class panel | ~1400 LOC |
| `flutter_ui/lib/widgets/dsp/internal_processor_editor_window.dart` | UPDATE — 15 params | +50 |
| `crates/rf-dsp/tests/` ili inline | NOVO — 25+ testova | +350 |

**Ukupno Rust:** ~600 LOC neto (DSP + wrapper + tests)
**Ukupno Flutter:** ~1450 LOC (UI rewrite + inspector)

---

## ACCEPTANCE CRITERIA

| Kriterijum | Metrika |
|------------|---------|
| No metallic ringing | Long decay (>5s) smooth, no flutter |
| Frequency-shaped decay | Low/High mult audibly different |
| Width > 100% natural | M/S processing, no artifacts |
| Distance = ER proximity | Audible close→far transition |
| Character = density + mod | Higher = denser, more chorused tail |
| Thickness = denser tail | A/B audible difference at 0.0 vs 1.0 |
| Self-ducking works | Loud input → wet attenuated, silence → wet returns |
| Freeze = infinite sustain | No decay when freeze=true, immediate resume on false |
| CPU ≤ +40% vs Freeverb | Profile with `cargo bench` |
| Determinism | Bit-exact across runs (fixed seed) |
| No heap alloc in process() | Verified by inspection |
| All 25+ tests pass | `cargo test -p rf-dsp` |
| FFI roundtrip 15 params | set/get all 15 indices |
| UI mastering-grade izgled | Miran, tehnički, bez gaming estetike |
| 3 panel veličine | S/M/L responsivno, inspector collapse |
| Decay EQ + Post EQ curves | Obe vidljive, interaktivne band dots |
| Piano strip toggle | 52px strip na dnu display-a |
| Inspector panel | Freq/Amount/Q/Type za selektovani band |
| Knob 300° arc | Value ring + glow + tooltip |
| Style segmented pill | 5 opcija bez override ponašanja |
| Freeze momentary | Press=on, release=off |
| Bez bounce/spring | Sve tranzicije easeOutCubic 120-180ms |

---

## NE RADIMO (SKIP)

| Stavka | Razlog |
|--------|--------|
| PostToneEQ unutar reverba | Duplikacija — EQ već postoji u insert chain |
| 12 ER tapova | 8 dovoljno za slot audio middleware |
| Runtime heap allocation | Zabranjeno po CLAUDE.md audio thread rules |
| `nalgebra` dependency | Hand-write 8×8 Hadamard — 60 LOC, nema dependency |
| Convolution reverb promene | Potpuno nepromenjen |
| Gate knob u UI | Koristi Gate processor iz insert chain-a |
| Gate DSP unutar reverba | Duplikacija — već postoji kao zaseban InsertProcessor |
| Sidechain input (eksterni) | Zahteva promenu InsertProcessor trait-a — koristimo self-duck |
