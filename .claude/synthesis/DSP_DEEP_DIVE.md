# FluxForge Studio — DSP Processors Deep Dive

> Detaljne specifikacije DSP procesora iz Pro Tools, Logic, Cubase i REAPER

---

## 1. EQ COMPARISON — FluxForge vs Competition

### 1.1 Feature Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EQ FEATURE COMPARISON                               │
├───────────────────┬──────────┬──────────┬──────────┬──────────┬────────────┤
│ Feature           │ Pro-Q 3  │ Frequency│ Channel  │ ReaEQ    │ FluxForge  │
│                   │ (FabF.)  │ (Cubase) │ EQ(Logic)│ (REAPER) │ (Target)   │
├───────────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Max Bands         │ 24       │ 8        │ 8        │ ∞        │ 64 ✓       │
│ Filter Types      │ 9        │ 6        │ 8        │ 5        │ 10 ✓       │
│ Phase Modes       │ 3        │ 2        │ 2        │ 1        │ 3 ✓        │
│ Dynamic EQ        │ ✓        │ ✓        │ ✗        │ ✗        │ ✓ Per-band │
│ M/S Processing    │ ✓        │ ✓        │ ✗        │ ✗        │ ✓ Per-band │
│ Sidechain         │ External │ 8 inputs │ 1 input  │ ✗        │ ✓ Per-band │
│ Max Slope         │ 96dB/oct │ 48dB/oct │ 48dB/oct │ 12dB/oct │ 96dB/oct ✓ │
│ Spectrum          │ ✓ GPU    │ ✓        │ ✓        │ ✓        │ ✓ GPU 8K   │
│ Oversampling      │ 4x       │ 4x       │ ✗        │ 16x      │ 16x ✓      │
│ Precision         │ 64-bit   │ 64-bit   │ 64-bit   │ 64-bit   │ 64-bit ✓   │
│ Auto-gain         │ ✓        │ ✓        │ ✗        │ ✗        │ ✓ LUFS     │
│ Match EQ          │ ✓        │ ✓        │ ✗        │ ✗        │ ✓          │
│ Piano Roll        │ ✓        │ ✗        │ ✗        │ ✗        │ ✓          │
│ SIMD Optimized    │ SSE      │ SSE      │ ARM      │ SSE      │ AVX-512 ✓  │
├───────────────────┴──────────┴──────────┴──────────┴──────────┴────────────┤
│ LEGEND: ✓ = Has feature, ✗ = Missing, Per-band = Each band independent    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Filter Types Deep Dive

```
FLUXFORGE EQ — 10 FILTER TYPES
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. BELL (Parametric)                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Standard parametric EQ curve                                           ││
│  │ • Parameters: Frequency, Gain, Q                                        ││
│  │ • Q range: 0.1 (very wide) to 100 (surgical)                           ││
│  │ • Gain: ±30dB                                                           ││
│  │ • Uses: Tone shaping, surgical cuts, resonance removal                  ││
│  │                                                                          ││
│  │ Transfer function (TDF-II biquad):                                       ││
│  │ H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)              ││
│  │                                                                          ││
│  │        ─────╲      ╱─────                                               ││
│  │             ╲    ╱                                                      ││
│  │              ╲──╱   Boost                                               ││
│  │ ─────────────────────────────                                           ││
│  │              ╱──╲   Cut                                                 ││
│  │             ╱    ╲                                                      ││
│  │        ─────╱      ╲─────                                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  2. LOW SHELF                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Boosts/cuts everything below frequency                                ││
│  │ • Parameters: Frequency, Gain, Slope (6/12/18/24 dB/oct)               ││
│  │ • Gain: ±24dB                                                           ││
│  │ • Uses: Bass boost, low-end warmth, rumble reduction                   ││
│  │                                                                          ││
│  │        Boost                                                             ││
│  │ ───────────╲                                                            ││
│  │             ╲────────────────                                           ││
│  │                                                                          ││
│  │ ─────────────────────────────  Unity                                    ││
│  │                                                                          ││
│  │             ╱────────────────                                           ││
│  │ ───────────╱                                                            ││
│  │        Cut                                                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  3. HIGH SHELF                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Boosts/cuts everything above frequency                                ││
│  │ • Parameters: Frequency, Gain, Slope                                    ││
│  │ • Uses: Air/presence, brightness, harshness taming                     ││
│  │                                                                          ││
│  │                         Boost                                            ││
│  │ ────────────────╱───────────                                            ││
│  │                ╱                                                         ││
│  │                                                                          ││
│  │ ─────────────────────────────  Unity                                    ││
│  │                ╲                                                         ││
│  │ ────────────────╲───────────                                            ││
│  │                         Cut                                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  4. LOW CUT (High-Pass Filter)                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Removes everything below cutoff                                       ││
│  │ • Slopes: 6, 12, 18, 24, 36, 48, 72, 96 dB/octave                      ││
│  │ • Uses: Rumble removal, tightening bass, cleaning mud                  ││
│  │                                                                          ││
│  │ 96dB/oct = 16th order = incredibly steep                                ││
│  │                                                                          ││
│  │         ┌──────────────────                                             ││
│  │        ╱│                                                                ││
│  │       ╱ │ 96dB/oct                                                      ││
│  │      ╱  │                                                                ││
│  │     ╱   │                                                                ││
│  │ ───╱────│────────────────                                               ││
│  │         ↑                                                                ││
│  │      Cutoff                                                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  5. HIGH CUT (Low-Pass Filter)                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Removes everything above cutoff                                       ││
│  │ • Slopes: 6-96 dB/octave                                               ││
│  │ • Uses: Harshness removal, vintage sound, anti-aliasing                ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  6. NOTCH                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Surgical cut at specific frequency                                    ││
│  │ • Q can be extremely high (>100)                                       ││
│  │ • Uses: Hum removal (50/60Hz), resonance kill                          ││
│  │                                                                          ││
│  │ ────────────╲╱────────────                                              ││
│  │              ▽ Deep notch                                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  7. BAND-PASS                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Passes only frequencies around center                                 ││
│  │ • Parameters: Frequency, Q (bandwidth)                                  ││
│  │ • Uses: Radio effect, telephone effect, isolation                      ││
│  │                                                                          ││
│  │         ╱──╲                                                            ││
│  │        ╱    ╲                                                           ││
│  │ ──────╱      ╲──────                                                    ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  8. TILT                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Tilts entire spectrum around pivot point                             ││
│  │ • One control: Tilt amount                                             ││
│  │ • Uses: Quick brightness/warmth adjustment                             ││
│  │                                                                          ││
│  │ ────────────────╱                 Bright                                ││
│  │                ╳ Pivot                                                  ││
│  │ ╱────────────────                 Warm                                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  9. ALL-PASS                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • No amplitude change — only phase shift                               ││
│  │ • Uses: Phase correction, creative effects                             ││
│  │ • Key for linear phase EQ implementation                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  10. FLAT TILT SHELF (Pro-Q style)                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Shelf with adjustable tilt slope                                      ││
│  │ • Combines shelf + tilt characteristics                                ││
│  │ • Uses: Mastering, subtle coloration                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Phase Modes Implementation

```
PHASE MODE COMPARISON
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. MINIMUM PHASE (Default)                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Pros:                                                                    ││
│  │ • Zero latency (causal filter)                                          ││
│  │ • Natural sound for most applications                                   ││
│  │ • Low CPU usage                                                         ││
│  │                                                                          ││
│  │ Cons:                                                                    ││
│  │ • Phase shift around filter frequency                                   ││
│  │ • Can cause pre-ringing on transients (at steep slopes)                ││
│  │                                                                          ││
│  │ Implementation: Standard TDF-II biquad cascade                          ││
│  │ Latency: 0 samples                                                      ││
│  │ CPU: ~5% of linear phase                                                ││
│  │                                                                          ││
│  │ Use when:                                                                ││
│  │ • Recording/monitoring (need zero latency)                              ││
│  │ • Mixing (phase coherence not critical)                                 ││
│  │ • CPU constrained                                                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  2. LINEAR PHASE                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Pros:                                                                    ││
│  │ • Zero phase distortion (constant group delay)                          ││
│  │ • Perfect phase coherence between bands                                 ││
│  │ • Ideal for mastering                                                   ││
│  │                                                                          ││
│  │ Cons:                                                                    ││
│  │ • Significant latency (FFT-based)                                       ││
│  │ • Pre-ringing on transients (symmetrical impulse response)              ││
│  │ • Higher CPU usage                                                      ││
│  │                                                                          ││
│  │ Implementation:                                                          ││
│  │ ┌─────────────────────────────────────────────────────────────────┐     ││
│  │ │                                                                  │     ││
│  │ │  Signal → FFT → Magnitude × Filter → IFFT → Output              │     ││
│  │ │                     ↓                                           │     ││
│  │ │               Phase = 0                                         │     ││
│  │ │                                                                  │     ││
│  │ └─────────────────────────────────────────────────────────────────┘     ││
│  │                                                                          ││
│  │ Latency: FFT size / 2 samples (e.g., 4096 samples = ~93ms @ 44.1kHz)   ││
│  │ CPU: ~20x minimum phase                                                 ││
│  │                                                                          ││
│  │ Use when:                                                                ││
│  │ • Mastering (phase-perfect summing)                                     ││
│  │ • Parallel processing (avoiding comb filtering)                         ││
│  │ • Surgical work where latency is acceptable                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  3. HYBRID (FluxForge Innovation)                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Concept: Best of both worlds                                            ││
│  │                                                                          ││
│  │ Implementation:                                                          ││
│  │ ┌─────────────────────────────────────────────────────────────────┐     ││
│  │ │                                                                  │     ││
│  │ │  Signal ─┬─→ [Min Phase] ──┬──→ Crossfade → Output              │     ││
│  │ │          │                  │        ↑                          │     ││
│  │ │          └─→ [Lin Phase] ──┘        │                          │     ││
│  │ │                                  Blend                          │     ││
│  │ │                               (0-100%)                          │     ││
│  │ │                                                                  │     ││
│  │ └─────────────────────────────────────────────────────────────────┘     ││
│  │                                                                          ││
│  │ Features:                                                                ││
│  │ • Adjustable blend (0% = min phase, 100% = linear phase)               ││
│  │ • Frequency-dependent blending (low = linear, high = minimum)          ││
│  │ • Adaptive pre-ring suppression                                        ││
│  │                                                                          ││
│  │ Latency: Variable based on blend amount                                 ││
│  │ CPU: Between min and linear phase                                       ││
│  │                                                                          ││
│  │ Use when:                                                                ││
│  │ • Need some phase linearity with less latency                          ││
│  │ • Want to control pre-ringing vs phase trade-off                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Rust EQ Implementation

```rust
// crates/rf-dsp/src/eq/parametric.rs

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════
// FILTER TYPE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FilterType {
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
    Notch,
    BandPass,
    Tilt,
    AllPass,
    FlatTiltShelf,
}

// ═══════════════════════════════════════════════════════════════════════════
// FILTER SLOPE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FilterSlope {
    Db6,   // 1st order
    Db12,  // 2nd order
    Db18,  // 3rd order
    Db24,  // 4th order
    Db36,  // 6th order
    Db48,  // 8th order
    Db72,  // 12th order
    Db96,  // 16th order
}

impl FilterSlope {
    pub fn order(&self) -> usize {
        match self {
            Self::Db6 => 1,
            Self::Db12 => 2,
            Self::Db18 => 3,
            Self::Db24 => 4,
            Self::Db36 => 6,
            Self::Db48 => 8,
            Self::Db72 => 12,
            Self::Db96 => 16,
        }
    }

    /// Number of biquad stages needed
    pub fn biquad_stages(&self) -> usize {
        (self.order() + 1) / 2
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BIQUAD FILTER (TDF-II)
// ═══════════════════════════════════════════════════════════════════════════

/// Transposed Direct Form II biquad — optimal for 64-bit floating point
#[derive(Clone, Default)]
pub struct BiquadTDF2 {
    // Coefficients
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,

    // State
    z1: f64,
    z2: f64,
}

impl BiquadTDF2 {
    /// Process single sample (inline for SIMD optimization)
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }

    /// Process block of samples
    #[inline]
    pub fn process_block(&mut self, samples: &mut [f64]) {
        for sample in samples.iter_mut() {
            *sample = self.process(*sample);
        }
    }

    /// Reset state (call on discontinuity)
    pub fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }

    /// Calculate coefficients for bell filter
    pub fn calc_bell(&mut self, freq: f64, gain_db: f64, q: f64, sample_rate: f64) {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let a0 = 1.0 + alpha / a;

        self.b0 = (1.0 + alpha * a) / a0;
        self.b1 = (-2.0 * cos_omega) / a0;
        self.b2 = (1.0 - alpha * a) / a0;
        self.a1 = self.b1; // Same as b1 for bell
        self.a2 = (1.0 - alpha / a) / a0;
    }

    /// Calculate coefficients for low shelf
    pub fn calc_low_shelf(&mut self, freq: f64, gain_db: f64, slope: f64, sample_rate: f64) {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / 2.0 * ((a + 1.0 / a) * (1.0 / slope - 1.0) + 2.0).sqrt();
        let sqrt_a = a.sqrt();

        let a0 = (a + 1.0) + (a - 1.0) * cos_omega + 2.0 * sqrt_a * alpha;

        self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_omega + 2.0 * sqrt_a * alpha)) / a0;
        self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_omega)) / a0;
        self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_omega - 2.0 * sqrt_a * alpha)) / a0;
        self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_omega)) / a0;
        self.a2 = ((a + 1.0) + (a - 1.0) * cos_omega - 2.0 * sqrt_a * alpha) / a0;
    }

    /// Calculate coefficients for high shelf
    pub fn calc_high_shelf(&mut self, freq: f64, gain_db: f64, slope: f64, sample_rate: f64) {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / 2.0 * ((a + 1.0 / a) * (1.0 / slope - 1.0) + 2.0).sqrt();
        let sqrt_a = a.sqrt();

        let a0 = (a + 1.0) - (a - 1.0) * cos_omega + 2.0 * sqrt_a * alpha;

        self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_omega + 2.0 * sqrt_a * alpha)) / a0;
        self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_omega)) / a0;
        self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_omega - 2.0 * sqrt_a * alpha)) / a0;
        self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_omega)) / a0;
        self.a2 = ((a + 1.0) - (a - 1.0) * cos_omega - 2.0 * sqrt_a * alpha) / a0;
    }

    /// Calculate coefficients for high-pass (low cut)
    pub fn calc_high_pass(&mut self, freq: f64, q: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let a0 = 1.0 + alpha;

        self.b0 = ((1.0 + cos_omega) / 2.0) / a0;
        self.b1 = (-(1.0 + cos_omega)) / a0;
        self.b2 = self.b0;
        self.a1 = (-2.0 * cos_omega) / a0;
        self.a2 = (1.0 - alpha) / a0;
    }

    /// Calculate coefficients for low-pass (high cut)
    pub fn calc_low_pass(&mut self, freq: f64, q: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let a0 = 1.0 + alpha;

        self.b0 = ((1.0 - cos_omega) / 2.0) / a0;
        self.b1 = (1.0 - cos_omega) / a0;
        self.b2 = self.b0;
        self.a1 = (-2.0 * cos_omega) / a0;
        self.a2 = (1.0 - alpha) / a0;
    }

    /// Calculate coefficients for notch
    pub fn calc_notch(&mut self, freq: f64, q: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let a0 = 1.0 + alpha;

        self.b0 = 1.0 / a0;
        self.b1 = (-2.0 * cos_omega) / a0;
        self.b2 = self.b0;
        self.a1 = self.b1;
        self.a2 = (1.0 - alpha) / a0;
    }

    /// Calculate coefficients for all-pass
    pub fn calc_all_pass(&mut self, freq: f64, q: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let a0 = 1.0 + alpha;

        self.b0 = (1.0 - alpha) / a0;
        self.b1 = (-2.0 * cos_omega) / a0;
        self.b2 = (1.0 + alpha) / a0;
        self.a1 = self.b1;
        self.a2 = self.b0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ BAND
// ═══════════════════════════════════════════════════════════════════════════

/// Single EQ band with all parameters
#[derive(Clone)]
pub struct EqBand {
    /// Filter type
    pub filter_type: FilterType,

    /// Center frequency (Hz)
    pub frequency: f64,

    /// Gain (dB) — for bell, shelf
    pub gain_db: f64,

    /// Q factor / bandwidth
    pub q: f64,

    /// Slope for cuts/shelves
    pub slope: FilterSlope,

    /// Enabled
    pub enabled: bool,

    /// Solo this band
    pub solo: bool,

    // ─────────────────────────────────────────────────────────────────────
    // DYNAMIC EQ
    // ─────────────────────────────────────────────────────────────────────

    /// Dynamic mode enabled
    pub dynamic_enabled: bool,

    /// Threshold (dBFS)
    pub threshold_db: f64,

    /// Ratio (1:1 to inf:1)
    pub ratio: f64,

    /// Attack time (ms)
    pub attack_ms: f64,

    /// Release time (ms)
    pub release_ms: f64,

    /// Range (max gain reduction/boost)
    pub range_db: f64,

    // ─────────────────────────────────────────────────────────────────────
    // PROCESSING MODE
    // ─────────────────────────────────────────────────────────────────────

    /// Processing mode (L/R, M/S, specific channel)
    pub processing_mode: ProcessingMode,

    // ─────────────────────────────────────────────────────────────────────
    // INTERNAL STATE
    // ─────────────────────────────────────────────────────────────────────

    /// Biquad stages (for steep slopes)
    biquads_left: Vec<BiquadTDF2>,
    biquads_right: Vec<BiquadTDF2>,

    /// Dynamic gain envelope follower
    envelope: f64,

    /// Current dynamic gain
    dynamic_gain: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ProcessingMode {
    #[default]
    Stereo,      // L and R together
    LeftOnly,    // Left channel only
    RightOnly,   // Right channel only
    Mid,         // Mid only
    Side,        // Side only
}

impl EqBand {
    pub fn new(filter_type: FilterType) -> Self {
        Self {
            filter_type,
            frequency: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            slope: FilterSlope::Db12,
            enabled: true,
            solo: false,
            dynamic_enabled: false,
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            range_db: 12.0,
            processing_mode: ProcessingMode::Stereo,
            biquads_left: Vec::new(),
            biquads_right: Vec::new(),
            envelope: 0.0,
            dynamic_gain: 1.0,
        }
    }

    /// Recalculate coefficients (call when params change)
    pub fn update_coefficients(&mut self, sample_rate: f64) {
        let num_stages = match self.filter_type {
            FilterType::LowCut | FilterType::HighCut => self.slope.biquad_stages(),
            _ => 1,
        };

        // Resize biquad arrays if needed
        self.biquads_left.resize(num_stages, BiquadTDF2::default());
        self.biquads_right.resize(num_stages, BiquadTDF2::default());

        // Calculate coefficients for each stage
        for (stage, (left, right)) in self.biquads_left.iter_mut()
            .zip(self.biquads_right.iter_mut())
            .enumerate()
        {
            // Q adjustment for cascaded filters
            let stage_q = if num_stages > 1 {
                Self::butterworth_q(num_stages, stage)
            } else {
                self.q
            };

            match self.filter_type {
                FilterType::Bell => {
                    left.calc_bell(self.frequency, self.gain_db, self.q, sample_rate);
                    right.calc_bell(self.frequency, self.gain_db, self.q, sample_rate);
                }
                FilterType::LowShelf => {
                    left.calc_low_shelf(self.frequency, self.gain_db, 1.0, sample_rate);
                    right.calc_low_shelf(self.frequency, self.gain_db, 1.0, sample_rate);
                }
                FilterType::HighShelf => {
                    left.calc_high_shelf(self.frequency, self.gain_db, 1.0, sample_rate);
                    right.calc_high_shelf(self.frequency, self.gain_db, 1.0, sample_rate);
                }
                FilterType::LowCut => {
                    left.calc_high_pass(self.frequency, stage_q, sample_rate);
                    right.calc_high_pass(self.frequency, stage_q, sample_rate);
                }
                FilterType::HighCut => {
                    left.calc_low_pass(self.frequency, stage_q, sample_rate);
                    right.calc_low_pass(self.frequency, stage_q, sample_rate);
                }
                FilterType::Notch => {
                    left.calc_notch(self.frequency, self.q, sample_rate);
                    right.calc_notch(self.frequency, self.q, sample_rate);
                }
                FilterType::AllPass => {
                    left.calc_all_pass(self.frequency, self.q, sample_rate);
                    right.calc_all_pass(self.frequency, self.q, sample_rate);
                }
                _ => {} // Tilt, BandPass, FlatTiltShelf — implement similarly
            }
        }
    }

    /// Butterworth Q values for cascaded filters
    fn butterworth_q(total_stages: usize, stage: usize) -> f64 {
        let order = total_stages * 2;
        let k = stage as f64;
        let n = order as f64;
        1.0 / (2.0 * (PI * (2.0 * k + 1.0) / (2.0 * n)).cos())
    }

    /// Process stereo pair
    #[inline]
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        if !self.enabled {
            return;
        }

        match self.processing_mode {
            ProcessingMode::Stereo => {
                self.process_channel(left, true);
                self.process_channel(right, false);
            }
            ProcessingMode::LeftOnly => {
                self.process_channel(left, true);
            }
            ProcessingMode::RightOnly => {
                self.process_channel(right, false);
            }
            ProcessingMode::Mid | ProcessingMode::Side => {
                // Convert to M/S, process, convert back
                self.process_mid_side(left, right);
            }
        }
    }

    #[inline]
    fn process_channel(&mut self, samples: &mut [f64], is_left: bool) {
        let biquads = if is_left {
            &mut self.biquads_left
        } else {
            &mut self.biquads_right
        };

        for biquad in biquads.iter_mut() {
            biquad.process_block(samples);
        }
    }

    fn process_mid_side(&mut self, left: &mut [f64], right: &mut [f64]) {
        // Convert L/R to M/S
        for i in 0..left.len() {
            let l = left[i];
            let r = right[i];
            left[i] = (l + r) * 0.5;  // Mid
            right[i] = (l - r) * 0.5; // Side
        }

        // Process appropriate channel
        match self.processing_mode {
            ProcessingMode::Mid => self.process_channel(left, true),
            ProcessingMode::Side => self.process_channel(right, false),
            _ => unreachable!(),
        }

        // Convert M/S back to L/R
        for i in 0..left.len() {
            let m = left[i];
            let s = right[i];
            left[i] = m + s;
            right[i] = m - s;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// 64-BAND EQ
// ═══════════════════════════════════════════════════════════════════════════

/// Full 64-band parametric EQ
pub struct ParametricEq {
    /// All bands
    pub bands: Vec<EqBand>,

    /// Phase mode
    pub phase_mode: PhaseMode,

    /// Sample rate
    sample_rate: f64,

    /// Auto-gain enabled
    pub auto_gain: bool,

    /// Auto-gain compensation value
    auto_gain_value: f64,

    /// Output gain
    pub output_gain_db: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum PhaseMode {
    #[default]
    Minimum,
    Linear,
    Hybrid { blend: u8 }, // 0-100%
}

impl ParametricEq {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            bands: Vec::with_capacity(64),
            phase_mode: PhaseMode::Minimum,
            sample_rate,
            auto_gain: false,
            auto_gain_value: 1.0,
            output_gain_db: 0.0,
        }
    }

    /// Add a new band
    pub fn add_band(&mut self, filter_type: FilterType) -> usize {
        if self.bands.len() >= 64 {
            return self.bands.len() - 1;
        }

        let mut band = EqBand::new(filter_type);
        band.update_coefficients(self.sample_rate);
        self.bands.push(band);
        self.bands.len() - 1
    }

    /// Remove band by index
    pub fn remove_band(&mut self, index: usize) -> bool {
        if index < self.bands.len() {
            self.bands.remove(index);
            true
        } else {
            false
        }
    }

    /// Process stereo audio
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        // Process through all enabled bands
        for band in &mut self.bands {
            band.process(left, right);
        }

        // Apply output gain
        let gain = db_to_linear(self.output_gain_db) * self.auto_gain_value;
        if (gain - 1.0).abs() > f64::EPSILON {
            for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                *l *= gain;
                *r *= gain;
            }
        }
    }

    /// Update sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for band in &mut self.bands {
            band.update_coefficients(sample_rate);
        }
    }
}

#[inline(always)]
fn db_to_linear(db: f64) -> f64 {
    if db <= -144.0 {
        0.0
    } else {
        10.0_f64.powf(db / 20.0)
    }
}
```

---

## 2. DYNAMICS — Best From Each DAW

### 2.1 Compressor Comparison

```
COMPRESSOR FEATURE COMPARISON
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌───────────────┬──────────┬──────────┬──────────┬──────────┬────────────┐│
│  │ Feature       │ Pro-C 2  │ Dynamics │ Compressor│ ReaComp │ FluxForge  ││
│  │               │ (FabF.)  │ (Cubase) │ (Logic)  │ (REAPER) │ (Target)   ││
│  ├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤│
│  │ Circuit Types │ 8        │ 4        │ 7        │ 1        │ 8 ✓        ││
│  │ Min Attack    │ 0.005ms  │ 0.1ms    │ 0.5ms    │ 0ms      │ 0ms ✓      ││
│  │ Max Attack    │ 250ms    │ 100ms    │ 200ms    │ 1000ms   │ 500ms ✓    ││
│  │ Lookahead     │ ✓        │ ✗        │ ✗        │ ✓        │ ✓          ││
│  │ Parallel Mix  │ ✓        │ ✓        │ ✗        │ ✓        │ ✓ Per-band ││
│  │ Sidechain EQ  │ ✓        │ ✓        │ ✓        │ ✗        │ ✓ Full EQ  ││
│  │ Auto Release  │ ✓        │ ✗        │ ✓        │ ✗        │ ✓ Program  ││
│  │ Knee          │ 0-72dB   │ 0-20dB   │ Fixed    │ ∞        │ 0-100dB ✓  ││
│  │ External SC   │ ✓        │ ✓        │ ✓        │ ✓        │ ✓          ││
│  │ MIDI Trigger  │ ✗        │ ✗        │ ✗        │ ✓        │ ✓          ││
│  │ Multiband     │ Separate │ Yes      │ Separate │ Separate │ ✓ Inline   ││
│  └───────────────┴──────────┴──────────┴──────────┴──────────┴────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Circuit Types (From Logic)

```
COMPRESSOR CIRCUIT MODELS
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. PLATINUM (Clean VCA)                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Transparent, surgical compression                                      ││
│  │ • Fastest attack possible (0ms with lookahead)                          ││
│  │ • Linear transfer function                                              ││
│  │ • Use: Mastering, transparent dynamic control                           ││
│  │                                                                          ││
│  │ Character: None — pristine, uncolored                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  2. VCA (SSL-style)                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Punchy, aggressive                                                     ││
│  │ • Fast attack, program-dependent release                                ││
│  │ • Slight harmonic enhancement                                           ││
│  │ • Use: Drums, bus compression, mix glue                                 ││
│  │                                                                          ││
│  │ Character: Punch, presence, subtle saturation                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  3. FET (1176-style)                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Ultra-fast attack (<0.02ms)                                           ││
│  │ • Aggressive harmonic distortion                                        ││
│  │ • "All-buttons-in" mode available                                       ││
│  │ • Use: Vocals, drums, aggressive sound design                           ││
│  │                                                                          ││
│  │ Character: Grit, aggression, presence                                   ││
│  │                                                                          ││
│  │ Non-linear: Output = input × (1 + k × |input|²)                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  4. OPTO (LA-2A style)                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Slow, smooth attack (10-100ms typical)                                ││
│  │ • Program-dependent release                                             ││
│  │ • Gentle, musical compression                                           ││
│  │ • Use: Vocals, bass, acoustic instruments                               ││
│  │                                                                          ││
│  │ Character: Smooth, warm, vintage                                        ││
│  │                                                                          ││
│  │ Photo-resistor model: τ = base_τ × (1 + signal_level)                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  5. VINTAGE VCA (Neve/API style)                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Transformer coloration                                                 ││
│  │ • Soft clipping on peaks                                                ││
│  │ • Harmonic enhancement                                                  ││
│  │ • Use: Full mix, drums, anything needing "warmth"                       ││
│  │                                                                          ││
│  │ Character: Thick, warm, "expensive"                                     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  6. VINTAGE FET (Distressor style)                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • FET + additional harmonic generation                                  ││
│  │ • Multiple distortion modes                                             ││
│  │ • British mode (even harmonics)                                         ││
│  │ • Use: Drums, aggressive vocals, parallel compression                   ││
│  │                                                                          ││
│  │ Character: Aggressive, saturated, "in your face"                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  7. VINTAGE OPTO (Fairchild style)                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Tube saturation                                                       ││
│  │ • Variable-mu compression                                               ││
│  │ • Very slow, program-dependent timing                                   ││
│  │ • Use: Mastering, full mix, vintage vibe                                ││
│  │                                                                          ││
│  │ Character: Lush, vintage, "expensive" tube warmth                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  8. BUS (Glue compression)                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • SSL Bus Compressor style                                              ││
│  │ • Fixed attack times (0.1, 0.3, 1, 3, 10, 30ms)                        ││
│  │ • Auto release option                                                   ││
│  │ • Use: Mix bus, drum bus, group compression                             ││
│  │                                                                          ││
│  │ Character: Glue, punch, cohesion                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Rust Compressor Implementation

```rust
// crates/rf-dsp/src/dynamics/compressor.rs

use std::f64::consts::E;

// ═══════════════════════════════════════════════════════════════════════════
// CIRCUIT TYPE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum CircuitType {
    #[default]
    Platinum,    // Clean VCA
    Vca,         // SSL-style
    Fet,         // 1176-style
    Opto,        // LA-2A style
    VintageVca,  // Neve/API
    VintageFet,  // Distressor
    VintageOpto, // Fairchild
    Bus,         // SSL Bus Comp
}

impl CircuitType {
    /// Get default attack time for circuit type
    pub fn default_attack_ms(&self) -> f64 {
        match self {
            Self::Platinum => 1.0,
            Self::Vca => 0.3,
            Self::Fet => 0.02,
            Self::Opto => 20.0,
            Self::VintageVca => 1.0,
            Self::VintageFet => 0.1,
            Self::VintageOpto => 50.0,
            Self::Bus => 0.3,
        }
    }

    /// Get saturation amount
    pub fn saturation_amount(&self) -> f64 {
        match self {
            Self::Platinum => 0.0,
            Self::Vca => 0.1,
            Self::Fet => 0.3,
            Self::Opto => 0.05,
            Self::VintageVca => 0.2,
            Self::VintageFet => 0.4,
            Self::VintageOpto => 0.25,
            Self::Bus => 0.15,
        }
    }

    /// Get harmonic profile (even/odd ratio)
    pub fn harmonic_profile(&self) -> (f64, f64) {
        // (even_harmonics, odd_harmonics)
        match self {
            Self::Platinum => (0.0, 0.0),
            Self::Vca => (0.3, 0.7),
            Self::Fet => (0.2, 0.8),       // Predominantly odd
            Self::Opto => (0.6, 0.4),      // More even
            Self::VintageVca => (0.5, 0.5),
            Self::VintageFet => (0.3, 0.7),
            Self::VintageOpto => (0.7, 0.3), // Tube = more even
            Self::Bus => (0.4, 0.6),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPRESSOR
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone)]
pub struct Compressor {
    // ─────────────────────────────────────────────────────────────────────
    // PARAMETERS
    // ─────────────────────────────────────────────────────────────────────

    /// Circuit type (affects sound character)
    pub circuit: CircuitType,

    /// Threshold (dBFS)
    pub threshold_db: f64,

    /// Ratio (1.0 = no compression, infinity = limiter)
    pub ratio: f64,

    /// Attack time (ms)
    pub attack_ms: f64,

    /// Release time (ms)
    pub release_ms: f64,

    /// Knee width (dB)
    pub knee_db: f64,

    /// Makeup gain (dB)
    pub makeup_db: f64,

    /// Mix (dry/wet) — 0.0 = dry, 1.0 = wet
    pub mix: f64,

    /// Lookahead (ms)
    pub lookahead_ms: f64,

    /// Auto makeup gain
    pub auto_makeup: bool,

    /// Auto release (program-dependent)
    pub auto_release: bool,

    // ─────────────────────────────────────────────────────────────────────
    // SIDECHAIN
    // ─────────────────────────────────────────────────────────────────────

    /// External sidechain enabled
    pub external_sidechain: bool,

    /// Sidechain high-pass frequency (Hz), 0 = disabled
    pub sidechain_hpf: f64,

    /// Sidechain low-pass frequency (Hz), 0 = disabled
    pub sidechain_lpf: f64,

    // ─────────────────────────────────────────────────────────────────────
    // INTERNAL STATE
    // ─────────────────────────────────────────────────────────────────────

    /// Current gain reduction (linear)
    envelope: f64,

    /// Sample rate
    sample_rate: f64,

    /// Attack coefficient
    attack_coeff: f64,

    /// Release coefficient
    release_coeff: f64,

    /// Lookahead buffer
    lookahead_buffer: Vec<[f64; 2]>,
    lookahead_index: usize,
    lookahead_samples: usize,

    /// Sidechain filters
    sc_hpf: crate::eq::BiquadTDF2,
    sc_lpf: crate::eq::BiquadTDF2,

    /// Gain reduction meter (for UI)
    pub current_gr_db: f64,
}

impl Compressor {
    pub fn new(sample_rate: f64) -> Self {
        let mut comp = Self {
            circuit: CircuitType::Platinum,
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 1.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_db: 0.0,
            mix: 1.0,
            lookahead_ms: 0.0,
            auto_makeup: false,
            auto_release: false,
            external_sidechain: false,
            sidechain_hpf: 0.0,
            sidechain_lpf: 0.0,
            envelope: 1.0,
            sample_rate,
            attack_coeff: 0.0,
            release_coeff: 0.0,
            lookahead_buffer: Vec::new(),
            lookahead_index: 0,
            lookahead_samples: 0,
            sc_hpf: crate::eq::BiquadTDF2::default(),
            sc_lpf: crate::eq::BiquadTDF2::default(),
            current_gr_db: 0.0,
        };

        comp.update_coefficients();
        comp
    }

    /// Update internal coefficients when parameters change
    pub fn update_coefficients(&mut self) {
        // Attack/release coefficients
        self.attack_coeff = (-1.0 / (self.attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();

        // Lookahead buffer
        self.lookahead_samples = (self.lookahead_ms * 0.001 * self.sample_rate) as usize;
        if self.lookahead_samples > 0 {
            self.lookahead_buffer.resize(self.lookahead_samples, [0.0; 2]);
        } else {
            self.lookahead_buffer.clear();
        }

        // Sidechain filters
        if self.sidechain_hpf > 0.0 {
            self.sc_hpf.calc_high_pass(self.sidechain_hpf, 0.707, self.sample_rate);
        }
        if self.sidechain_lpf > 0.0 {
            self.sc_lpf.calc_low_pass(self.sidechain_lpf, 0.707, self.sample_rate);
        }
    }

    /// Process stereo audio
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64], sidechain: Option<(&[f64], &[f64])>) {
        let num_samples = left.len();
        let makeup_gain = db_to_linear(self.makeup_db);

        for i in 0..num_samples {
            // Get detector input (sidechain or main)
            let (sc_l, sc_r) = if let Some((sc_left, sc_right)) = sidechain {
                if self.external_sidechain {
                    (sc_left[i], sc_right[i])
                } else {
                    (left[i], right[i])
                }
            } else {
                (left[i], right[i])
            };

            // Apply sidechain filtering
            let sc_l_filtered = self.filter_sidechain(sc_l);
            let sc_r_filtered = self.filter_sidechain(sc_r);

            // Detector (peak or RMS depending on circuit)
            let detector_level = self.detect(sc_l_filtered, sc_r_filtered);
            let detector_db = linear_to_db(detector_level);

            // Compute gain reduction
            let gr_db = self.compute_gain_reduction(detector_db);

            // Apply attack/release envelope
            self.apply_envelope(gr_db);

            // Current gain (linear)
            let gain = db_to_linear(-self.envelope) * makeup_gain;

            // Apply to signal (with lookahead if enabled)
            let (out_l, out_r) = if self.lookahead_samples > 0 {
                self.apply_with_lookahead(left[i], right[i], gain)
            } else {
                (left[i] * gain, right[i] * gain)
            };

            // Apply mix
            left[i] = left[i] * (1.0 - self.mix) + out_l * self.mix;
            right[i] = right[i] * (1.0 - self.mix) + out_r * self.mix;

            // Apply circuit saturation
            if self.circuit.saturation_amount() > 0.0 {
                left[i] = self.apply_saturation(left[i]);
                right[i] = self.apply_saturation(right[i]);
            }
        }

        // Update meter
        self.current_gr_db = -self.envelope;
    }

    /// Sidechain filter
    #[inline]
    fn filter_sidechain(&mut self, sample: f64) -> f64 {
        let mut s = sample;
        if self.sidechain_hpf > 0.0 {
            s = self.sc_hpf.process(s);
        }
        if self.sidechain_lpf > 0.0 {
            s = self.sc_lpf.process(s);
        }
        s
    }

    /// Detector (varies by circuit type)
    #[inline]
    fn detect(&self, left: f64, right: f64) -> f64 {
        match self.circuit {
            // Peak detection for fast circuits
            CircuitType::Fet | CircuitType::VintageFet | CircuitType::Platinum => {
                left.abs().max(right.abs())
            }
            // RMS-ish for slower circuits
            CircuitType::Opto | CircuitType::VintageOpto => {
                ((left * left + right * right) * 0.5).sqrt()
            }
            // Hybrid for VCA
            _ => {
                // Weighted average of peak and RMS
                let peak = left.abs().max(right.abs());
                let rms = ((left * left + right * right) * 0.5).sqrt();
                peak * 0.6 + rms * 0.4
            }
        }
    }

    /// Compute gain reduction with soft knee
    #[inline]
    fn compute_gain_reduction(&self, input_db: f64) -> f64 {
        let threshold = self.threshold_db;
        let ratio = self.ratio;
        let knee = self.knee_db;

        if knee > 0.0 && input_db > threshold - knee / 2.0 && input_db < threshold + knee / 2.0 {
            // Soft knee region
            let x = input_db - threshold + knee / 2.0;
            let gain_reduction = (1.0 / ratio - 1.0) * (x * x) / (2.0 * knee);
            -gain_reduction
        } else if input_db >= threshold + knee / 2.0 {
            // Above knee — full compression
            (input_db - threshold) * (1.0 - 1.0 / ratio)
        } else {
            // Below threshold — no compression
            0.0
        }
    }

    /// Apply attack/release envelope
    #[inline]
    fn apply_envelope(&mut self, target_gr_db: f64) {
        let target = target_gr_db.max(0.0);

        let coeff = if target > self.envelope {
            self.attack_coeff
        } else {
            if self.auto_release {
                // Program-dependent release
                let release_mod = (self.envelope / 20.0).min(1.0);
                self.release_coeff.powf(1.0 + release_mod)
            } else {
                self.release_coeff
            }
        };

        self.envelope = target + coeff * (self.envelope - target);
    }

    /// Apply with lookahead
    #[inline]
    fn apply_with_lookahead(&mut self, left: f64, right: f64, gain: f64) -> (f64, f64) {
        // Store current sample
        let delayed = self.lookahead_buffer[self.lookahead_index];
        self.lookahead_buffer[self.lookahead_index] = [left, right];

        // Advance index
        self.lookahead_index = (self.lookahead_index + 1) % self.lookahead_samples;

        // Return delayed sample with current gain
        (delayed[0] * gain, delayed[1] * gain)
    }

    /// Apply circuit saturation
    #[inline]
    fn apply_saturation(&self, sample: f64) -> f64 {
        let amount = self.circuit.saturation_amount();
        if amount <= 0.0 {
            return sample;
        }

        let (even, odd) = self.circuit.harmonic_profile();

        // Soft clip with harmonic character
        let saturated = if sample >= 0.0 {
            // Positive half: even harmonics add asymmetry
            let even_term = sample * sample * even * amount;
            let odd_term = sample.tanh() * odd;
            sample * (1.0 - amount) + (odd_term + even_term * 0.1) * amount
        } else {
            // Negative half
            let even_term = sample * sample * even * amount;
            let odd_term = sample.tanh() * odd;
            sample * (1.0 - amount) + (odd_term - even_term * 0.1) * amount
        };

        // Soft limit to prevent clipping
        saturated.tanh()
    }
}

#[inline(always)]
fn db_to_linear(db: f64) -> f64 {
    if db <= -144.0 { 0.0 } else { 10.0_f64.powf(db / 20.0) }
}

#[inline(always)]
fn linear_to_db(linear: f64) -> f64 {
    if linear <= 0.0 { -144.0 } else { 20.0 * linear.log10() }
}
```

---

## 3. REVERB — Best Algorithms

### 3.1 Reverb Type Comparison

```
REVERB ALGORITHM COMPARISON
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌───────────────┬──────────────┬─────────────┬────────────┬──────────────┐│
│  │ Type          │ CPU          │ Quality     │ Flexibility│ Use Case     ││
│  ├───────────────┼──────────────┼─────────────┼────────────┼──────────────┤│
│  │ Convolution   │ High         │ Excellent   │ Low        │ Realism      ││
│  │ Algorithmic   │ Low          │ Good        │ High       │ Creative     ││
│  │ Spectral      │ Medium       │ Excellent   │ High       │ Modern       ││
│  │ Hybrid        │ Medium-High  │ Excellent   │ High       │ Mastering    ││
│  └───────────────┴──────────────┴─────────────┴────────────┴──────────────┘│
│                                                                              │
│  FLUXFORGE TARGET: All 4 types                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Algorithmic Reverb Types

```
ALGORITHMIC REVERB ALGORITHMS
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. PLATE (EMT 140 / 240 style)                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Dense, smooth decay                                                    ││
│  │ • Metallic character                                                    ││
│  │ • No early reflections                                                  ││
│  │ • Use: Vocals, snare, strings                                           ││
│  │                                                                          ││
│  │ Implementation: All-pass diffuser network + feedback matrix             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  2. HALL (Large concert hall)                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Long pre-delay                                                         ││
│  │ • Smooth, natural decay                                                 ││
│  │ • Clear early reflections                                               ││
│  │ • Use: Orchestral, cinematic, pads                                      ││
│  │                                                                          ││
│  │ Implementation: FDN (Feedback Delay Network) + early reflection module  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  3. ROOM (Small/medium rooms)                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Short decay (0.3-1.5s)                                                ││
│  │ • Clear early reflections                                               ││
│  │ • Realistic room simulation                                             ││
│  │ • Use: Drums, acoustic instruments                                      ││
│  │                                                                          ││
│  │ Implementation: Image-source early reflections + FDN late              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  4. CHAMBER (Echo chamber)                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Bright character                                                       ││
│  │ • Dense early reflections                                               ││
│  │ • Medium decay                                                          ││
│  │ • Use: Vocals, vintage sound                                            ││
│  │                                                                          ││
│  │ Implementation: Multi-tap delay + diffusion                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  5. SPRING (Guitar amp style)                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Distinctive "boing" character                                         ││
│  │ • Non-linear decay                                                      ││
│  │ • Lo-fi but characterful                                                ││
│  │ • Use: Guitar, vintage, lo-fi                                           ││
│  │                                                                          ││
│  │ Implementation: Dispersive delay line + non-linear feedback             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  6. SHIMMER (Pitch-shifted)                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Pitch-shifted feedback (+12 or +7 semitones typical)                  ││
│  │ • Ethereal, otherworldly                                                ││
│  │ • Infinite build-up option                                              ││
│  │ • Use: Ambient, cinematic, guitar                                       ││
│  │                                                                          ││
│  │ Implementation: Reverb → Pitch shifter → Feedback                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  7. CHROMAVERB (Logic-style spectral)                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ • Per-frequency decay control                                           ││
│  │ • Extremely smooth                                                      ││
│  │ • Visual frequency display                                              ││
│  │ • Use: Any — most versatile                                             ││
│  │                                                                          ││
│  │ Implementation: FFT-based spectral processing                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Rust Reverb Implementation (FDN)

```rust
// crates/rf-dsp/src/reverb/fdn.rs

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════
// FEEDBACK DELAY NETWORK (FDN) REVERB
// ═══════════════════════════════════════════════════════════════════════════

/// 8-channel Feedback Delay Network reverb
pub struct FdnReverb {
    // ─────────────────────────────────────────────────────────────────────
    // PARAMETERS
    // ─────────────────────────────────────────────────────────────────────

    /// Reverb decay time (seconds)
    pub decay_time: f64,

    /// Room size (affects delay line lengths)
    pub room_size: f64,

    /// Pre-delay (ms)
    pub pre_delay_ms: f64,

    /// Damping (high frequency decay)
    pub damping: f64,

    /// Diffusion amount
    pub diffusion: f64,

    /// Low frequency decay multiplier
    pub low_decay_mult: f64,

    /// High frequency decay multiplier
    pub high_decay_mult: f64,

    /// Modulation rate (Hz)
    pub mod_rate: f64,

    /// Modulation depth
    pub mod_depth: f64,

    /// Mix (dry/wet)
    pub mix: f64,

    // ─────────────────────────────────────────────────────────────────────
    // INTERNAL STATE
    // ─────────────────────────────────────────────────────────────────────

    /// Sample rate
    sample_rate: f64,

    /// Delay lines (8 channels)
    delay_lines: [DelayLine; 8],

    /// Delay line lengths (prime numbers for diffusion)
    delay_lengths: [usize; 8],

    /// Feedback matrix (Hadamard)
    feedback_matrix: [[f64; 8]; 8],

    /// Feedback gains per delay line
    feedback_gains: [f64; 8],

    /// Damping filters (one per delay line)
    damping_filters: [OnePoleFilter; 8],

    /// Input diffusers (all-pass)
    input_diffusers: [AllPassFilter; 4],

    /// Pre-delay line
    pre_delay: DelayLine,

    /// Modulation LFOs
    mod_lfo: [f64; 8],
    mod_phase: f64,
}

impl FdnReverb {
    /// Prime delay line lengths for maximum diffusion
    const DELAY_PRIMES: [usize; 8] = [
        1033, 1399, 1747, 2017,  // Shorter (early)
        2711, 3163, 3571, 4001,  // Longer (late)
    ];

    pub fn new(sample_rate: f64) -> Self {
        let mut reverb = Self {
            decay_time: 2.0,
            room_size: 0.5,
            pre_delay_ms: 20.0,
            damping: 0.5,
            diffusion: 0.75,
            low_decay_mult: 1.0,
            high_decay_mult: 0.8,
            mod_rate: 0.5,
            mod_depth: 0.002,
            mix: 0.3,
            sample_rate,
            delay_lines: Default::default(),
            delay_lengths: Self::DELAY_PRIMES,
            feedback_matrix: Self::hadamard_8(),
            feedback_gains: [0.0; 8],
            damping_filters: Default::default(),
            input_diffusers: Default::default(),
            pre_delay: DelayLine::new(sample_rate as usize), // Max 1 second
            mod_lfo: [0.0; 8],
            mod_phase: 0.0,
        };

        reverb.update_parameters();
        reverb
    }

    /// Update internal state when parameters change
    pub fn update_parameters(&mut self) {
        // Scale delay lengths by room size
        for i in 0..8 {
            let base = Self::DELAY_PRIMES[i] as f64;
            self.delay_lengths[i] = (base * (0.5 + self.room_size * 0.5)) as usize;

            // Ensure minimum length
            self.delay_lengths[i] = self.delay_lengths[i].max(64);

            // Resize delay line
            self.delay_lines[i].resize(self.delay_lengths[i] * 2);
        }

        // Calculate feedback gains for desired decay time
        for i in 0..8 {
            let delay_sec = self.delay_lengths[i] as f64 / self.sample_rate;
            // RT60 formula: feedback = 10^(-3 * delay / RT60)
            self.feedback_gains[i] = 10.0_f64.powf(-3.0 * delay_sec / self.decay_time);
        }

        // Update damping filters
        let damping_freq = 2000.0 + (1.0 - self.damping) * 18000.0;
        for filter in &mut self.damping_filters {
            filter.set_cutoff(damping_freq, self.sample_rate);
        }

        // Update pre-delay
        let pre_delay_samples = (self.pre_delay_ms * 0.001 * self.sample_rate) as usize;
        self.pre_delay.set_delay(pre_delay_samples);

        // Update input diffusers
        let diffuser_delays = [142, 107, 379, 277]; // Prime numbers
        for (i, diffuser) in self.input_diffusers.iter_mut().enumerate() {
            diffuser.set_delay(diffuser_delays[i]);
            diffuser.set_feedback(self.diffusion * 0.7);
        }
    }

    /// Generate Hadamard feedback matrix (unitary, preserves energy)
    fn hadamard_8() -> [[f64; 8]; 8] {
        let h = 1.0 / (8.0_f64).sqrt();
        let mut m = [[0.0; 8]; 8];

        for i in 0..8 {
            for j in 0..8 {
                // Hadamard pattern
                let bits = i & j;
                let parity = bits.count_ones() % 2;
                m[i][j] = if parity == 0 { h } else { -h };
            }
        }

        m
    }

    /// Process stereo audio
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let num_samples = left.len();

        for i in 0..num_samples {
            // Pre-delay
            let input_mono = (left[i] + right[i]) * 0.5;
            let pre_delayed = self.pre_delay.process(input_mono);

            // Input diffusion
            let mut diffused = pre_delayed;
            for diffuser in &mut self.input_diffusers {
                diffused = diffuser.process(diffused);
            }

            // Feed into delay lines
            let mut delay_outputs = [0.0; 8];
            for j in 0..8 {
                // Read from delay line with modulation
                let mod_offset = (self.mod_lfo[j] * self.mod_depth * self.delay_lengths[j] as f64) as i32;
                delay_outputs[j] = self.delay_lines[j].read_with_offset(mod_offset);
            }

            // Apply feedback matrix
            let mut feedback_inputs = [0.0; 8];
            for j in 0..8 {
                for k in 0..8 {
                    feedback_inputs[j] += self.feedback_matrix[j][k] * delay_outputs[k];
                }

                // Apply damping and feedback gain
                feedback_inputs[j] = self.damping_filters[j].process(feedback_inputs[j]);
                feedback_inputs[j] *= self.feedback_gains[j];
            }

            // Write back to delay lines (add input)
            let input_gain = 1.0 / 8.0_f64.sqrt();
            for j in 0..8 {
                let input = feedback_inputs[j] + diffused * input_gain;
                self.delay_lines[j].write(input);
            }

            // Sum outputs (stereo decorrelation)
            let wet_left = delay_outputs[0] + delay_outputs[2] + delay_outputs[4] + delay_outputs[6];
            let wet_right = delay_outputs[1] + delay_outputs[3] + delay_outputs[5] + delay_outputs[7];

            // Mix
            left[i] = left[i] * (1.0 - self.mix) + wet_left * self.mix * 0.25;
            right[i] = right[i] * (1.0 - self.mix) + wet_right * self.mix * 0.25;

            // Update modulation
            self.mod_phase += self.mod_rate / self.sample_rate;
            if self.mod_phase >= 1.0 {
                self.mod_phase -= 1.0;
            }

            for j in 0..8 {
                let phase_offset = j as f64 / 8.0;
                self.mod_lfo[j] = ((self.mod_phase + phase_offset) * 2.0 * PI).sin();
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Default)]
struct DelayLine {
    buffer: Vec<f64>,
    write_index: usize,
    delay: usize,
}

impl DelayLine {
    fn new(max_size: usize) -> Self {
        Self {
            buffer: vec![0.0; max_size],
            write_index: 0,
            delay: max_size / 2,
        }
    }

    fn resize(&mut self, size: usize) {
        if self.buffer.len() < size {
            self.buffer.resize(size, 0.0);
        }
    }

    fn set_delay(&mut self, delay: usize) {
        self.delay = delay.min(self.buffer.len() - 1);
    }

    #[inline]
    fn write(&mut self, sample: f64) {
        self.buffer[self.write_index] = sample;
        self.write_index = (self.write_index + 1) % self.buffer.len();
    }

    #[inline]
    fn read_with_offset(&self, offset: i32) -> f64 {
        let read_index = (self.write_index as i32 - self.delay as i32 + offset)
            .rem_euclid(self.buffer.len() as i32) as usize;
        self.buffer[read_index]
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        let output = self.read_with_offset(0);
        self.write(input);
        output
    }
}

#[derive(Clone, Default)]
struct OnePoleFilter {
    y1: f64,
    a: f64,
}

impl OnePoleFilter {
    fn set_cutoff(&mut self, freq: f64, sample_rate: f64) {
        let omega = 2.0 * PI * freq / sample_rate;
        self.a = (-omega).exp();
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        self.y1 = input * (1.0 - self.a) + self.y1 * self.a;
        self.y1
    }
}

#[derive(Clone, Default)]
struct AllPassFilter {
    buffer: Vec<f64>,
    index: usize,
    feedback: f64,
}

impl AllPassFilter {
    fn set_delay(&mut self, delay: usize) {
        self.buffer.resize(delay, 0.0);
    }

    fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(-0.99, 0.99);
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        let delayed = self.buffer[self.index];
        let output = -input * self.feedback + delayed;
        self.buffer[self.index] = input + delayed * self.feedback;
        self.index = (self.index + 1) % self.buffer.len();
        output
    }
}
```

---

## 4. SUMMARY — FluxForge DSP Advantage

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               FLUXFORGE DSP — COMPREHENSIVE PROCESSOR SUITE                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  EQ (rf-dsp/eq):                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ 64 bands (3-8x more than competition)                                 ││
│  │ ✓ 10 filter types (Bell, Shelf, Cut, Notch, Tilt, AllPass, etc.)       ││
│  │ ✓ 3 phase modes (Minimum, Linear, Hybrid)                               ││
│  │ ✓ Per-band dynamic EQ                                                   ││
│  │ ✓ Per-band M/S processing                                               ││
│  │ ✓ Per-band sidechain                                                    ││
│  │ ✓ 96dB/oct slopes (16th order!)                                         ││
│  │ ✓ GPU-accelerated spectrum analyzer                                     ││
│  │ ✓ 16x oversampling option                                               ││
│  │ ✓ LUFS-based auto-gain                                                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  DYNAMICS (rf-dsp/dynamics):                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ 8 circuit types (Platinum, VCA, FET, Opto, Vintage, Bus)             ││
│  │ ✓ 0ms to 500ms attack                                                   ││
│  │ ✓ True lookahead (up to 10ms)                                           ││
│  │ ✓ Per-band parallel mix                                                 ││
│  │ ✓ Full sidechain EQ                                                     ││
│  │ ✓ Program-dependent auto release                                        ││
│  │ ✓ Variable knee (0-100dB)                                               ││
│  │ ✓ External sidechain                                                    ││
│  │ ✓ MIDI trigger output                                                   ││
│  │ ✓ Unlimited multiband                                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  REVERB (rf-dsp/reverb):                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Convolution (true impulse responses)                                  ││
│  │ ✓ 7 algorithmic types (Plate, Hall, Room, Chamber, Spring, Shimmer,    ││
│  │   ChromaVerb-style spectral)                                            ││
│  │ ✓ 8-channel FDN for natural diffusion                                   ││
│  │ ✓ Modulation for movement                                               ││
│  │ ✓ Per-frequency decay control                                           ││
│  │ ✓ Surround support (up to 7.1.4)                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  OPTIMIZATION:                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ 64-bit double precision throughout                                    ││
│  │ ✓ AVX-512/AVX2/SSE4.2/NEON SIMD                                        ││
│  │ ✓ Lock-free parameter updates                                           ││
│  │ ✓ Zero allocation in audio path                                         ││
│  │ ✓ Per-processor oversampling (2x-16x)                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Sources:**
- FabFilter Pro-Q 3, Pro-C 2 specifications
- Cubase Pro 14 Frequency EQ, Dynamics
- Logic Pro Compressor circuit types, ChromaVerb
- REAPER ReaEQ, ReaComp, ReaVerb
- Academic DSP literature (DAFX, Julius O. Smith)
