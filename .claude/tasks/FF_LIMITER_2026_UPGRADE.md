# FF Limiter — Pro-L 2 Class Upgrade

**Created:** 2026-02-15
**Status:** PLANNED
**Priority:** P0 (Core DSP)
**Spec:** `.claude/specs/FF_LIMITER_SPEC.md` (TBD)

---

## Current State

### What Works (4 params, 2 meters)
- Basic threshold/ceiling limiting
- One-pole IIR release smoothing
- True peak detection via oversampled peak (up to 8x)
- 7-tap halfband filter for oversampling

### What's Dead (10 of 14 UI features)
| UI Feature | Status | Reason |
|------------|--------|--------|
| Input Gain (`_gain`) | DEAD | No FFI param |
| Attack (`_attack`) | DEAD | No FFI param |
| Lookahead slider (`_lookahead`) | DEAD | Hardcoded 1.5ms in engine |
| Style selector (8 styles) | DEAD | Enum only in Dart |
| Channel Link (`_channelLink`) | DEAD | No FFI param |
| Unity Gain (`_unityGain`) | DEAD | No FFI param |
| LUFS meters | DEAD | Values not from engine |
| Meter Scale (K-12/14/20) | DEAD | UI only |
| GR History graph | PARTIAL | Only reads single GR value |
| True Peak toggle | WORKS | Via `advancedGetTruePeak8x()` |

### Files
| File | LOC | Role |
|------|-----|------|
| `crates/rf-dsp/src/dynamics.rs:968-1164` | ~196 | TruePeakLimiter struct |
| `crates/rf-dsp/src/dynamics.rs:1167-1252` | ~85 | Simple Limiter (mono) |
| `crates/rf-engine/src/dsp_wrappers.rs:960-1068` | ~108 | TruePeakLimiterWrapper (FFI) |
| `flutter_ui/lib/widgets/fabfilter/fabfilter_limiter_panel.dart` | ~891 | UI Panel |

---

## Target: Pro-L 2 Class Architecture

### Signal Flow
```
Input Trim (-12..+12 dB)
  → M/S Encode (optional)
  → Upsample (2x/4x/8x/16x/32x polyphase FIR)
  → Lookahead Ring Buffer (0-20ms, user-controllable)
  → Detector (sample peak + 4x true peak)
  → GainPlanner (future-looking envelope from lookahead)
  → Multi-Stage Gain Engine
  │   ├─ Stage A: Transient Containment (fast attack, < 0.1ms)
  │   └─ Stage B: Sustain/Release Shaper (program-dependent)
  → Stereo Linker (0-100%, optional freq-aware)
  → Ceiling + Safety Stage (dBTP enforcement)
  → Downsample (matched polyphase FIR)
  → Dither (triangular / noise-shaped, offline)
  → M/S Decode (if M/S active)
  → Mix (parallel limiting, 0-100%)
  → Output
```

### 8 Engine-Level Styles

Each style defines DIFFERENT DSP laws — NOT presets:

| Style | Transient Attack | Release Law | Anti-Pump | Character |
|-------|-----------------|-------------|-----------|-----------|
| 0: Transparent | 0.05ms | Adaptive program-dep | Max | Clean, invisible |
| 1: Punchy | 0.2ms | Fast-slow dual stage | Medium | Punch-through |
| 2: Dynamic | 0.1ms | Program-dependent | High | Preserves dynamics |
| 3: Aggressive | 0.02ms | Very fast fixed | Low | In-your-face |
| 4: Bus | 0.5ms | Slow glue | High | Bus/stem glue |
| 5: Safe | 0.1ms | Medium conservative | Max | Broadcast safe |
| 6: Modern | 0.05ms | Adaptive fast | Medium | Modern loud |
| 7: Allround | 0.1ms | Balanced | Medium | Default |

### Parameters (14 total)

| Idx | Param | Range | Default | Unit |
|-----|-------|-------|---------|------|
| 0 | Input Trim | -12..+12 | 0.0 | dB |
| 1 | Threshold | -30..0 | 0.0 | dB |
| 2 | Ceiling | -3..0 | -0.3 | dBTP |
| 3 | Release | 1..1000 | 100 | ms |
| 4 | Attack | 0.01..10 | 0.1 | ms |
| 5 | Lookahead | 0..20 | 5.0 | ms |
| 6 | Style | 0..7 | 7 | enum |
| 7 | Oversampling | 0..5 | 1 | enum (1x/2x/4x/8x/16x/32x) |
| 8 | Stereo Link | 0..100 | 100 | % |
| 9 | M/S Mode | 0/1 | 0 | bool |
| 10 | Mix | 0..100 | 100 | % |
| 11 | Dither Bits | 0..4 | 0 | enum (off/8/12/16/24) |
| 12 | Latency Profile | 0..2 | 1 | enum (ZeroLat/HQ/Offline) |
| 13 | Channel Config | 0..2 | 0 | enum (Stereo/Dual Mono/Mid-Side) |

### Meters (7 total)

| Idx | Meter | Unit | Update |
|-----|-------|------|--------|
| 0 | GR Left | dB | Per-block |
| 1 | GR Right | dB | Per-block |
| 2 | Input Peak L | dBFS | Per-block |
| 3 | Input Peak R | dBFS | Per-block |
| 4 | Output True Peak L | dBTP | Per-block |
| 5 | Output True Peak R | dBTP | Per-block |
| 6 | GR Max (hold) | dB | Peak hold, 2s decay |

### Latency Profiles

| Profile | Lookahead | Oversampling | Use Case |
|---------|-----------|-------------|----------|
| Zero-Lat | 0ms (no lookahead) | 1x | Live monitoring |
| HQ | 2-10ms | 2-4x | Real-time mastering |
| Offline Max | 10-20ms | 16-32x | Offline render |

---

## Build Phases (10 faza)

### F1: Foundation — `params[14]` + Input Trim + Mix
**Files:** `dynamics.rs`, `dsp_wrappers.rs`
**LOC:** ~150

- [ ] Add `params: [f64; 14]` stored array to TruePeakLimiterWrapper
- [ ] Fix `get_param()` to return from stored array
- [ ] Add `set_param()` for all 14 indices with range clamping
- [ ] Add Input Trim: multiply input by `db_to_linear(trim_db)` before processing
- [ ] Add Mix (parallel): `output = dry * (1-mix) + wet * mix`
- [ ] Update `num_params()` → 14

**Tests (5):**
- [ ] All params read back correctly after set
- [ ] Input trim +6dB doubles amplitude
- [ ] Mix 0% = bypass, 100% = full wet
- [ ] Parameter clamping at boundaries
- [ ] Default values correct

### F2: GainPlanner — Future-Looking Envelope
**Files:** `dynamics.rs`
**LOC:** ~200

- [ ] `GainPlanner` struct with fixed-size ring buffer `[f64; MAX_LOOKAHEAD_SAMPLES]`
- [ ] `MAX_LOOKAHEAD_SAMPLES = 960` (20ms @ 48kHz)
- [ ] User-controllable lookahead (0-20ms via param 5)
- [ ] `plan()` method: scan ahead, find worst peak, generate smooth attack ramp
- [ ] Attack ramp uses raised-cosine window (no clicks)
- [ ] Replace current `if peak > threshold` with GainPlanner output

**Tests (6):**
- [ ] Lookahead 0ms = zero-latency mode (instant attack)
- [ ] Lookahead 5ms = 5ms pre-attack ramp before transient
- [ ] Lookahead 20ms = full 20ms ramp
- [ ] No overshoot past ceiling
- [ ] Smooth gain curve (no discontinuities)
- [ ] Ring buffer wraps correctly

### F3: Multi-Stage Gain Engine
**Files:** `dynamics.rs`
**LOC:** ~250

- [ ] `GainStageA` — Transient Containment
  - Fast attack (< 0.1ms sample-by-sample)
  - Instant peak limiting for transients
  - Output: fast GR envelope
- [ ] `GainStageB` — Sustain/Release Shaper
  - Program-dependent release
  - Dual time constant (fast + slow)
  - Anti-pumping smoothing
  - Output: smooth GR envelope
- [ ] Final GR = `min(stage_a_gr, stage_b_gr)` (tighter wins)
- [ ] Replace current single-stage gain with two-stage

**Tests (8):**
- [ ] Stage A catches transients faster than Stage B
- [ ] Stage B provides smooth sustained limiting
- [ ] Combined GR never exceeds ceiling
- [ ] Program-dependent release: fast release on transient, slow on sustained
- [ ] Anti-pumping: bass-heavy signal doesn't cause audible pumping
- [ ] Dual time constant: 50ms fast + 300ms slow
- [ ] No GR oscillation on steady-state signal
- [ ] Stage A alone = brick-wall limiter behavior

### F4: 8 Engine-Level Styles
**Files:** `dynamics.rs`
**LOC:** ~200

- [ ] `LimiterStyle` enum with 8 variants
- [ ] Each style defines:
  - `transient_attack_ms: f64`
  - `fast_release_ms: f64`
  - `slow_release_ms: f64`
  - `anti_pump_strength: f64` (0.0-1.0)
  - `release_curve: ReleaseCurve` (Linear/Log/Exp/Adaptive)
  - `sustain_sensitivity: f64`
- [ ] `StyleParams::from_style(style)` → concrete DSP constants
- [ ] Style param (index 6) switches active style
- [ ] GainStageA and GainStageB read constants from active style

**Tests (8):**
- [ ] Each style produces different GR curve on same input
- [ ] Transparent: minimal coloration, fast recovery
- [ ] Aggressive: maximum loudness, fast attack
- [ ] Bus: slow glue, minimal transient damage
- [ ] Safe: never overshoots, conservative
- [ ] Style switch mid-stream: smooth transition (no click)
- [ ] All 8 styles produce valid output (no NaN/Inf)
- [ ] Default style (7=Allround) matches current behavior approximately
- [ ] Style doesn't affect ceiling enforcement

### F5: Polyphase Oversampling (do 32x)
**Files:** `dynamics.rs`
**LOC:** ~300

- [ ] Replace 7-tap HalfbandFilter with proper polyphase FIR
- [ ] Filter design: Kaiser window, 15-tap for 2x, 31-tap for 4x+
- [ ] Stopband attenuation > 100dB
- [ ] Passband ripple < 0.01dB
- [ ] Oversampling enum: X1, X2, X4, X8, X16, X32
- [ ] X16 and X32 only available in Offline profile (param 12)
- [ ] Fixed-size coefficient arrays (no Vec)
- [ ] Cascaded 2x stages for higher ratios (4x = 2x→2x, 8x = 2x→2x→2x)

**Tests (7):**
- [ ] 2x: alias rejection > 100dB above Nyquist/2
- [ ] 4x: true peak detection accuracy < 0.1dB error
- [ ] 8x: matches reference ITU-R BS.1770 true peak
- [ ] 16x: offline quality, ISP-compliant
- [ ] 32x: maximum quality, no aliasing artifacts
- [ ] Cascaded stages: correct gain through chain
- [ ] No heap allocation in process path

### F6: Stereo Linker
**Files:** `dynamics.rs`
**LOC:** ~80

- [ ] `stereo_link(gr_l, gr_r, link_pct)` → `(linked_l, linked_r)`
- [ ] Formula: `linked = lerp(independent, max(gr_l, gr_r), link / 100.0)`
- [ ] link=100%: both channels get same GR (tighter wins) — mono-compatible
- [ ] link=0%: fully independent L/R limiting — widest stereo
- [ ] Param 8 controls link percentage
- [ ] Applied AFTER multi-stage gain engine, BEFORE ceiling

**Tests (4):**
- [ ] Link 100%: L and R get identical GR
- [ ] Link 0%: L and R get independent GR
- [ ] Link 50%: GR is halfway between independent and linked
- [ ] Stereo image stability with program material

### F7: M/S Processing
**Files:** `dynamics.rs`
**LOC:** ~60

- [ ] M/S encode: `mid = (L+R)*0.5`, `side = (L-R)*0.5`
- [ ] M/S decode: `L = mid+side`, `R = mid-side`
- [ ] When M/S mode active (param 9=1):
  - Process mid and side as independent channels through limiter
  - Stereo link applies to M/S pair instead of L/R
- [ ] Gain compensation: encode/decode is unity gain

**Tests (4):**
- [ ] M/S roundtrip: encode→decode = unity (bit-exact)
- [ ] M/S limiting preserves stereo center
- [ ] Side-only content limited independently
- [ ] M/S + link interaction correct

### F8: Dither
**Files:** `dynamics.rs`
**LOC:** ~80

- [ ] Triangular PDF dither (sum of two uniform randoms)
- [ ] Noise-shaped dither (first-order error feedback)
- [ ] Bit depth options: off(0), 8(1), 12(2), 16(3), 24(4)
- [ ] Dither amplitude: `1.0 / (2^bits - 1)`
- [ ] Applied AFTER all processing, BEFORE output
- [ ] Offline only — skipped when param 11 = 0

**Tests (4):**
- [ ] Dither off: bit-exact passthrough
- [ ] 16-bit dither: noise floor at ~-96dBFS
- [ ] 24-bit dither: noise floor at ~-144dBFS
- [ ] Triangular PDF: correct probability distribution

### F9: 7 Meters + Latency Profiles
**Files:** `dynamics.rs`, `dsp_wrappers.rs`
**LOC:** ~120

- [ ] `meters: [f64; 7]` stored array
- [ ] Update meters per process block:
  - [0,1] GR L/R (current block peak GR)
  - [2,3] Input Peak L/R (pre-processing)
  - [4,5] Output True Peak L/R (post-processing)
  - [6] GR Max (peak hold with 2s decay)
- [ ] `get_meter()` returns from stored array
- [ ] Latency profiles:
  - Zero-Lat: lookahead=0, OS=1x, latency()=0
  - HQ: lookahead=user, OS=user, latency()=lookahead_samples + filter_latency
  - Offline: lookahead=max, OS=max, latency()=max

**Tests (5):**
- [ ] All 7 meters return valid values
- [ ] GR meters: negative dB when limiting
- [ ] Input peak: correct measurement pre-trim
- [ ] Output true peak: never exceeds ceiling
- [ ] GR max hold: holds peak for 2s, then decays

### F10: Vec → Fixed Arrays + RT Safety
**Files:** `dynamics.rs`
**LOC:** ~100

- [ ] Replace `Vec<Sample>` lookahead buffers with `[f64; MAX_BUFFER]`
- [ ] Replace `Vec<f64>` in HalfbandFilter with fixed arrays
- [ ] Verify: zero heap allocations in `process_sample()` and `process_stereo()`
- [ ] All ring buffers use modular indexing (`& (SIZE-1)` for power-of-2)
- [ ] Const-assert buffer sizes are power of 2

**Tests (3):**
- [ ] Process 1M samples without allocation (verified via custom allocator or code audit)
- [ ] Ring buffer wrap-around correct at all sizes
- [ ] Power-of-2 const assertion compiles

---

## Summary

| Metric | Current | Target |
|--------|---------|--------|
| Features | 4 | 17 |
| Params | 4 | 14 |
| Meters | 2 | 7 |
| Styles | 0 (engine) | 8 |
| Oversampling | 8x max | 32x max |
| Lookahead | 1.5ms fixed | 0-20ms user |
| Gain stages | 1 | 2 (transient + sustain) |
| M/S | No | Yes |
| Dither | No | Yes |
| Stereo Link | No | 0-100% |
| Tests | 0 | 54 |
| Dead UI features | 10 | 0 |

**Total estimated LOC:** ~1,540 new/modified Rust code
**Build order:** F1→F2→F3→F4→F5→F6→F7→F8→F9→F10
