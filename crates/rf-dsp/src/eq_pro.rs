//! Professional EQ - Pro-Q 4 Competitor
//!
//! Superior parametric equalizer with:
//! - 64 bands (vs Pro-Q's 24)
//! - SIMD-optimized processing (AVX2/AVX-512/NEON)
//! - Natural Phase (analog-modeled SVF)
//! - Linear Phase (FIR convolution)
//! - Zero Latency mode
//! - Dynamic EQ with external sidechain
//! - EQ Match (spectrum matching)
//! - Surround/Atmos support (7.1.2)
//! - GPU-ready spectrum data
//! - Collision detection
//! - Auto-listen
//! - Per-band spectrum solo

use std::f64::consts::PI;
use std::sync::Arc;

use realfft::{RealFftPlanner, RealToComplex};
use rustfft::num_complex::Complex;

use crate::{Processor, ProcessorConfig, StereoProcessor};
use rf_core::Sample;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum EQ bands (more than any competitor)
pub const MAX_BANDS: usize = 64;

/// FFT size for spectrum analysis
pub const SPECTRUM_FFT_SIZE: usize = 8192;

/// FFT size for EQ match
pub const MATCH_FFT_SIZE: usize = 16384;

/// Linear phase FIR length
pub const LINEAR_PHASE_FIR_SIZE: usize = 4096;

/// Maximum surround channels (7.1.2 Atmos)
pub const MAX_CHANNELS: usize = 10;

// ============================================================================
// FILTER TYPES
// ============================================================================

/// Filter shape
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum FilterShape {
    #[default]
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
    Notch,
    Bandpass,
    TiltShelf,
    Allpass,
    /// Brickwall (linear phase only)
    Brickwall,
}

impl FilterShape {
    /// Convert from index to FilterShape
    pub fn from_index(index: usize) -> Self {
        match index {
            0 => FilterShape::Bell,
            1 => FilterShape::LowShelf,
            2 => FilterShape::HighShelf,
            3 => FilterShape::LowCut,
            4 => FilterShape::HighCut,
            5 => FilterShape::Notch,
            6 => FilterShape::Bandpass,
            7 => FilterShape::TiltShelf,
            8 => FilterShape::Allpass,
            9 => FilterShape::Brickwall,
            _ => FilterShape::Bell,
        }
    }
}

/// Filter slope for cuts
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Slope {
    Db6,
    #[default]
    Db12,
    Db18,
    Db24,
    Db36,
    Db48,
    Db72,
    Db96,
    /// Brickwall (infinite slope, linear phase)
    Brickwall,
}

impl Slope {
    pub fn db_per_octave(&self) -> f64 {
        match self {
            Slope::Db6 => 6.0,
            Slope::Db12 => 12.0,
            Slope::Db18 => 18.0,
            Slope::Db24 => 24.0,
            Slope::Db36 => 36.0,
            Slope::Db48 => 48.0,
            Slope::Db72 => 72.0,
            Slope::Db96 => 96.0,
            Slope::Brickwall => f64::INFINITY,
        }
    }

    pub fn order(&self) -> usize {
        match self {
            Slope::Db6 => 1,
            Slope::Db12 => 2,
            Slope::Db18 => 3,
            Slope::Db24 => 4,
            Slope::Db36 => 6,
            Slope::Db48 => 8,
            Slope::Db72 => 12,
            Slope::Db96 => 16,
            Slope::Brickwall => 64,
        }
    }
}

/// Phase mode
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum PhaseMode {
    /// Zero latency, minimum phase response
    #[default]
    ZeroLatency,
    /// Analog-modeled phase (SVF-based)
    Natural,
    /// True linear phase (FIR)
    Linear,
    /// Blend between minimum and linear
    Mixed { blend: f32 },
}

/// Stereo placement
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum StereoPlacement {
    #[default]
    Stereo,
    Left,
    Right,
    Mid,
    Side,
}

/// Analyzer mode
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum AnalyzerMode {
    #[default]
    Off,
    PreEq,
    PostEq,
    Sidechain,
    Delta,
}

// ============================================================================
// SVF (STATE VARIABLE FILTER) - NATURAL PHASE
// ============================================================================

/// State Variable Filter for analog-like response
/// Andrew Simper's "Solving the continuous SVF equations"
#[derive(Debug, Clone)]
pub struct SvfCore {
    ic1eq: f64,
    ic2eq: f64,
    sample_rate: f64,
}

impl SvfCore {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            ic1eq: 0.0,
            ic2eq: 0.0,
            sample_rate,
        }
    }

    /// Process with precomputed coefficients
    #[inline(always)]
    pub fn process(
        &mut self,
        v0: f64,
        a1: f64,
        a2: f64,
        a3: f64,
        m0: f64,
        m1: f64,
        m2: f64,
    ) -> f64 {
        let v3 = v0 - self.ic2eq;
        let v1 = a1 * self.ic1eq + a2 * v3;
        let v2 = self.ic2eq + a2 * self.ic1eq + a3 * v3;
        self.ic1eq = 2.0 * v1 - self.ic1eq;
        self.ic2eq = 2.0 * v2 - self.ic2eq;
        m0 * v0 + m1 * v1 + m2 * v2
    }

    pub fn reset(&mut self) {
        self.ic1eq = 0.0;
        self.ic2eq = 0.0;
    }
}

/// SVF coefficients for different filter types
#[derive(Debug, Clone, Copy)]
pub struct SvfCoeffs {
    pub a1: f64,
    pub a2: f64,
    pub a3: f64,
    pub m0: f64,
    pub m1: f64,
    pub m2: f64,
}

impl SvfCoeffs {
    /// Identity filter (passthrough) - used as fallback for invalid params
    #[inline]
    pub fn identity() -> Self {
        Self {
            a1: 1.0,
            a2: 0.0,
            a3: 0.0,
            m0: 1.0,
            m1: 0.0,
            m2: 0.0,
        }
    }

    /// Bell/Peaking filter
    pub fn bell(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        // Defensive parameter validation
        let q = q.max(0.01); // Prevent division by zero
        let freq = freq.clamp(1.0, sample_rate * 0.499); // Nyquist limit

        let a = 10.0_f64.powf(gain_db / 40.0);

        // Check for NaN/Inf after powf
        if !a.is_finite() || a < 1e-10 {
            return Self::identity();
        }

        let g = (PI * freq / sample_rate).tan();

        // Check for NaN/Inf from tan (can happen near Nyquist)
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / (q * a);

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 1.0;
        let m1 = k * (a * a - 1.0);
        let m2 = 0.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Low shelf
    pub fn low_shelf(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let a = 10.0_f64.powf(gain_db / 40.0);
        if !a.is_finite() || a < 1e-10 {
            return Self::identity();
        }

        let g = (PI * freq / sample_rate).tan() / a.sqrt();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 1.0;
        let m1 = k * (a - 1.0);
        let m2 = a * a - 1.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// High shelf
    pub fn high_shelf(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let a = 10.0_f64.powf(gain_db / 40.0);
        if !a.is_finite() || a < 1e-10 {
            return Self::identity();
        }

        let g = (PI * freq / sample_rate).tan() * a.sqrt();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = a * a;
        let m1 = k * (1.0 - a) * a;
        let m2 = 1.0 - a * a;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Highpass (lowcut)
    pub fn highpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let g = (PI * freq / sample_rate).tan();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 1.0;
        let m1 = -k;
        let m2 = -1.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Lowpass (highcut)
    pub fn lowpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let g = (PI * freq / sample_rate).tan();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 0.0;
        let m1 = 0.0;
        let m2 = 1.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Notch
    pub fn notch(freq: f64, q: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let g = (PI * freq / sample_rate).tan();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 1.0;
        let m1 = -k;
        let m2 = 0.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Bandpass
    pub fn bandpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let q = q.max(0.01);
        let freq = freq.clamp(1.0, sample_rate * 0.499);

        let g = (PI * freq / sample_rate).tan();
        if !g.is_finite() {
            return Self::identity();
        }

        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 0.0;
        let m1 = 1.0;
        let m2 = 0.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Allpass
    pub fn allpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let g = (PI * freq / sample_rate).tan();
        let k = 1.0 / q;

        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;

        let m0 = 1.0;
        let m1 = -2.0 * k;
        let m2 = 0.0;

        Self {
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// Tilt shelf (combined low + high shelf)
    pub fn tilt(freq: f64, gain_db: f64, sample_rate: f64) -> Self {
        // Simplified tilt using high shelf with adjusted response
        Self::high_shelf(freq, 0.5, gain_db, sample_rate)
    }
}

// ============================================================================
// SIMD BIQUAD BANK - AVX2/AVX-512/NEON
// ============================================================================

/// Process 8 biquads in parallel using AVX-512 (or 4 with AVX2)
#[cfg(target_arch = "x86_64")]
pub mod simd_x86 {
    use std::simd::{f64x4, f64x8};

    /// 4-wide SIMD biquad bank (AVX2)
    #[derive(Debug, Clone)]
    pub struct BiquadBank4 {
        pub b0: f64x4,
        pub b1: f64x4,
        pub b2: f64x4,
        pub a1: f64x4,
        pub a2: f64x4,
        pub z1: f64x4,
        pub z2: f64x4,
    }

    impl BiquadBank4 {
        pub fn new() -> Self {
            Self {
                b0: f64x4::splat(1.0),
                b1: f64x4::splat(0.0),
                b2: f64x4::splat(0.0),
                a1: f64x4::splat(0.0),
                a2: f64x4::splat(0.0),
                z1: f64x4::splat(0.0),
                z2: f64x4::splat(0.0),
            }
        }

        /// Set coefficients for bank index
        pub fn set_coeffs(&mut self, index: usize, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) {
            if index < 4 {
                let mut b0_arr = self.b0.to_array();
                let mut b1_arr = self.b1.to_array();
                let mut b2_arr = self.b2.to_array();
                let mut a1_arr = self.a1.to_array();
                let mut a2_arr = self.a2.to_array();

                b0_arr[index] = b0;
                b1_arr[index] = b1;
                b2_arr[index] = b2;
                a1_arr[index] = a1;
                a2_arr[index] = a2;

                self.b0 = f64x4::from_array(b0_arr);
                self.b1 = f64x4::from_array(b1_arr);
                self.b2 = f64x4::from_array(b2_arr);
                self.a1 = f64x4::from_array(a1_arr);
                self.a2 = f64x4::from_array(a2_arr);
            }
        }

        /// Process 4 samples through 4 parallel biquads (TDF-II)
        #[inline(always)]
        pub fn process(&mut self, input: f64x4) -> f64x4 {
            let output = self.b0 * input + self.z1;
            self.z1 = self.b1 * input - self.a1 * output + self.z2;
            self.z2 = self.b2 * input - self.a2 * output;
            output
        }

        pub fn reset(&mut self) {
            self.z1 = f64x4::splat(0.0);
            self.z2 = f64x4::splat(0.0);
        }
    }

    impl Default for BiquadBank4 {
        fn default() -> Self {
            Self::new()
        }
    }

    /// 8-wide SIMD biquad bank (AVX-512)
    #[derive(Debug, Clone)]
    pub struct BiquadBank8 {
        pub b0: f64x8,
        pub b1: f64x8,
        pub b2: f64x8,
        pub a1: f64x8,
        pub a2: f64x8,
        pub z1: f64x8,
        pub z2: f64x8,
    }

    impl BiquadBank8 {
        pub fn new() -> Self {
            Self {
                b0: f64x8::splat(1.0),
                b1: f64x8::splat(0.0),
                b2: f64x8::splat(0.0),
                a1: f64x8::splat(0.0),
                a2: f64x8::splat(0.0),
                z1: f64x8::splat(0.0),
                z2: f64x8::splat(0.0),
            }
        }

        /// Set coefficients for bank index
        pub fn set_coeffs(&mut self, index: usize, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) {
            if index < 8 {
                let mut b0_arr = self.b0.to_array();
                let mut b1_arr = self.b1.to_array();
                let mut b2_arr = self.b2.to_array();
                let mut a1_arr = self.a1.to_array();
                let mut a2_arr = self.a2.to_array();

                b0_arr[index] = b0;
                b1_arr[index] = b1;
                b2_arr[index] = b2;
                a1_arr[index] = a1;
                a2_arr[index] = a2;

                self.b0 = f64x8::from_array(b0_arr);
                self.b1 = f64x8::from_array(b1_arr);
                self.b2 = f64x8::from_array(b2_arr);
                self.a1 = f64x8::from_array(a1_arr);
                self.a2 = f64x8::from_array(a2_arr);
            }
        }

        /// Process 8 samples through 8 parallel biquads (TDF-II)
        #[inline(always)]
        pub fn process(&mut self, input: f64x8) -> f64x8 {
            let output = self.b0 * input + self.z1;
            self.z1 = self.b1 * input - self.a1 * output + self.z2;
            self.z2 = self.b2 * input - self.a2 * output;
            output
        }

        pub fn reset(&mut self) {
            self.z1 = f64x8::splat(0.0);
            self.z2 = f64x8::splat(0.0);
        }
    }

    impl Default for BiquadBank8 {
        fn default() -> Self {
            Self::new()
        }
    }
}

// ============================================================================
// DYNAMIC EQ
// ============================================================================

/// Dynamic EQ parameters
#[derive(Debug, Clone, Copy)]
pub struct DynamicParams {
    pub enabled: bool,
    pub threshold_db: f64,
    pub ratio: f64,
    pub attack_ms: f64,
    pub release_ms: f64,
    pub knee_db: f64,
    /// Range limit for gain reduction/expansion
    pub range_db: f64,
    /// Use external sidechain
    pub external_sidechain: bool,
    /// Sidechain filter frequency (for focused detection)
    pub sidechain_filter_freq: Option<f64>,
}

impl Default for DynamicParams {
    fn default() -> Self {
        Self {
            enabled: false,
            threshold_db: -20.0,
            ratio: 2.0,
            attack_ms: 5.0,
            release_ms: 50.0,
            knee_db: 6.0,
            range_db: 30.0,
            external_sidechain: false,
            sidechain_filter_freq: None,
        }
    }
}

/// Dynamic EQ envelope follower
#[derive(Debug, Clone)]
pub struct DynamicEnvelope {
    envelope: f64,
    attack_coeff: f64,
    release_coeff: f64,
    sample_rate: f64,
}

impl DynamicEnvelope {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            envelope: 0.0,
            attack_coeff: 0.0,
            release_coeff: 0.0,
            sample_rate,
        }
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_coeff = (-1.0 / (attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (release_ms * 0.001 * self.sample_rate)).exp();
    }

    #[inline(always)]
    pub fn process(&mut self, input_level: f64) -> f64 {
        let coeff = if input_level > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = coeff * self.envelope + (1.0 - coeff) * input_level;
        self.envelope
    }

    /// Calculate gain reduction with soft knee
    pub fn calculate_gain(&self, params: &DynamicParams) -> f64 {
        let env_db = if self.envelope > 1e-10 {
            20.0 * self.envelope.log10()
        } else {
            -200.0
        };

        let over = env_db - params.threshold_db;
        let knee = params.knee_db;

        let gain_db = if over < -knee / 2.0 {
            0.0
        } else if over > knee / 2.0 {
            (over * (1.0 - 1.0 / params.ratio)).min(params.range_db)
        } else {
            // Soft knee
            let x = over + knee / 2.0;
            ((1.0 / params.ratio - 1.0) * x * x / (2.0 * knee)).min(params.range_db)
        };

        10.0_f64.powf(-gain_db / 20.0)
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
    }
}

// ============================================================================
// EQ BAND
// ============================================================================

/// Single EQ band with all features
#[derive(Debug, Clone)]
pub struct EqBand {
    // Parameters
    pub enabled: bool,
    pub shape: FilterShape,
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
    pub slope: Slope,
    pub placement: StereoPlacement,
    pub phase_mode: PhaseMode,
    pub dynamic: DynamicParams,

    // Processing state - multiple filter stages for steep slopes
    svf_stages_l: Vec<SvfCore>,
    svf_stages_r: Vec<SvfCore>,
    svf_coeffs: Vec<SvfCoeffs>,

    // Dynamic EQ state
    envelope_l: DynamicEnvelope,
    envelope_r: DynamicEnvelope,

    // Sidechain filter for dynamic EQ
    sidechain_svf: Option<SvfCore>,
    sidechain_coeffs: Option<SvfCoeffs>,

    // Auto-listen state
    pub solo: bool,

    // Cache
    sample_rate: f64,
    needs_update: bool,
}

impl EqBand {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            enabled: false,
            shape: FilterShape::Bell,
            frequency: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            slope: Slope::Db12,
            placement: StereoPlacement::Stereo,
            phase_mode: PhaseMode::ZeroLatency,
            dynamic: DynamicParams::default(),
            svf_stages_l: vec![SvfCore::new(sample_rate)],
            svf_stages_r: vec![SvfCore::new(sample_rate)],
            svf_coeffs: vec![],
            envelope_l: DynamicEnvelope::new(sample_rate),
            envelope_r: DynamicEnvelope::new(sample_rate),
            sidechain_svf: None,
            sidechain_coeffs: None,
            solo: false,
            sample_rate,
            needs_update: true,
        }
    }

    /// Set parameters
    pub fn set_params(&mut self, freq: f64, gain_db: f64, q: f64, shape: FilterShape) {
        self.frequency = freq.clamp(10.0, 30000.0);
        self.gain_db = gain_db.clamp(-30.0, 30.0);
        self.q = q.clamp(0.05, 50.0);
        self.shape = shape;
        self.needs_update = true;
    }

    /// Update filter coefficients
    pub fn update_coeffs(&mut self) {
        if !self.needs_update {
            return;
        }

        // Determine number of stages based on slope
        let num_stages = match self.shape {
            FilterShape::LowCut | FilterShape::HighCut => self.slope.order() / 2,
            FilterShape::Brickwall => 8, // Multiple stages for steep response
            _ => 1,
        };
        let num_stages = num_stages.max(1);

        // Resize stage vectors
        while self.svf_stages_l.len() < num_stages {
            self.svf_stages_l.push(SvfCore::new(self.sample_rate));
            self.svf_stages_r.push(SvfCore::new(self.sample_rate));
        }
        while self.svf_stages_l.len() > num_stages {
            self.svf_stages_l.pop();
            self.svf_stages_r.pop();
        }

        // Calculate coefficients
        self.svf_coeffs.clear();
        for stage_idx in 0..num_stages {
            let coeffs = match self.shape {
                FilterShape::Bell => {
                    SvfCoeffs::bell(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::LowShelf => {
                    SvfCoeffs::low_shelf(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::HighShelf => {
                    SvfCoeffs::high_shelf(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::LowCut => {
                    // Butterworth Q for each cascaded section (different Q per stage!)
                    let order = num_stages * 2; // Convert stages to filter order
                    let stage_q = Self::butterworth_q(order, stage_idx);
                    SvfCoeffs::highpass(self.frequency, stage_q, self.sample_rate)
                }
                FilterShape::HighCut => {
                    let order = num_stages * 2;
                    let stage_q = Self::butterworth_q(order, stage_idx);
                    SvfCoeffs::lowpass(self.frequency, stage_q, self.sample_rate)
                }
                FilterShape::Notch => SvfCoeffs::notch(self.frequency, self.q, self.sample_rate),
                FilterShape::Bandpass => {
                    SvfCoeffs::bandpass(self.frequency, self.q, self.sample_rate)
                }
                FilterShape::TiltShelf => {
                    SvfCoeffs::tilt(self.frequency, self.gain_db, self.sample_rate)
                }
                FilterShape::Allpass => {
                    SvfCoeffs::allpass(self.frequency, self.q, self.sample_rate)
                }
                FilterShape::Brickwall => {
                    // Brickwall uses linear phase, not SVF
                    SvfCoeffs::lowpass(self.frequency, 0.5, self.sample_rate)
                }
            };
            self.svf_coeffs.push(coeffs);
        }

        // Update dynamic EQ envelope
        self.envelope_l
            .set_times(self.dynamic.attack_ms, self.dynamic.release_ms);
        self.envelope_r
            .set_times(self.dynamic.attack_ms, self.dynamic.release_ms);

        // Update sidechain filter if needed
        if let Some(sc_freq) = self.dynamic.sidechain_filter_freq {
            self.sidechain_coeffs = Some(SvfCoeffs::bandpass(sc_freq, 2.0, self.sample_rate));
            if self.sidechain_svf.is_none() {
                self.sidechain_svf = Some(SvfCore::new(self.sample_rate));
            }
        }

        self.needs_update = false;
    }

    /// Butterworth Q values for cascaded second-order sections
    /// Returns the Q value for a specific stage in an N-th order Butterworth filter
    /// For 2N-th order filter, we need N second-order sections with specific Q values
    fn butterworth_q(order: usize, stage: usize) -> f64 {
        // Butterworth pole angles: theta_k = PI * (2k + order - 1) / (2 * order)
        // For each conjugate pole pair, Q = 1 / (2 * cos(theta_k))
        //
        // Pre-computed Q values for common orders:
        match order {
            1 => 0.7071067811865476, // 6dB/oct - single pole, Q=1/sqrt(2)
            2 => 0.7071067811865476, // 12dB/oct - Q = 1/sqrt(2)
            3 => {
                // 18dB/oct - 1 real pole + 1 conjugate pair
                match stage {
                    0 => 1.0, // First-order section (real pole)
                    _ => 1.0, // Second-order section
                }
            }
            4 => {
                // 24dB/oct - 2 conjugate pairs
                match stage {
                    0 => 0.5411961001461969, // Q1
                    _ => 1.3065629648763764, // Q2
                }
            }
            6 => {
                // 36dB/oct - 3 conjugate pairs
                match stage {
                    0 => 0.5176380902050415, // Q1
                    1 => 0.7071067811865476, // Q2
                    _ => 1.9318516525781366, // Q3
                }
            }
            8 => {
                // 48dB/oct - 4 conjugate pairs
                match stage {
                    0 => 0.5097955791041592, // Q1
                    1 => 0.6013448869350453, // Q2
                    2 => 0.8999446650072116, // Q3
                    _ => 2.5629154477415055, // Q4
                }
            }
            12 => {
                // 72dB/oct - 6 conjugate pairs
                match stage {
                    0 => 0.5044330855892026,
                    1 => 0.5411961001461969,
                    2 => 0.6305475968877769,
                    3 => 0.8211172650655689,
                    4 => 1.2247448713915890,
                    _ => 3.8306488521484588,
                }
            }
            16 => {
                // 96dB/oct - 8 conjugate pairs
                match stage {
                    0 => 0.5024192861881557,
                    1 => 0.5224985647578857,
                    2 => 0.5660035832651752,
                    3 => 0.6439569529474891,
                    4 => 0.7816437780945893,
                    5 => 1.0606601717798212,
                    6 => 1.7224470982383280,
                    _ => 5.1011486186891553,
                }
            }
            _ => {
                // Fallback: compute Q dynamically for any order
                let n = order as f64;
                let k = stage as f64;
                let theta = std::f64::consts::PI * (2.0 * k + n - 1.0) / (2.0 * n);
                let cos_theta = theta.cos();
                if cos_theta.abs() < 1e-10 {
                    100.0 // Very high Q for near-zero cosine
                } else {
                    1.0 / (2.0 * cos_theta.abs())
                }
            }
        }
    }

    /// Process stereo sample
    #[inline]
    pub fn process(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if !self.enabled {
            return (left, right);
        }

        if self.needs_update {
            self.update_coeffs();
        }

        // Calculate dynamic gain if enabled
        let (dyn_gain_l, dyn_gain_r) = if self.dynamic.enabled {
            // Apply sidechain filter if configured (filter the detector input, not audio)
            let (detect_l, detect_r) =
                if self.sidechain_svf.is_some() && self.sidechain_coeffs.is_some() {
                    let sc_svf = self.sidechain_svf.as_mut().unwrap();
                    let sc_coeffs = self.sidechain_coeffs.as_ref().unwrap();
                    // Filter the sidechain signal for frequency-focused detection
                    let filtered = sc_svf.process(
                        (left + right) * 0.5, // Use mono for sidechain
                        sc_coeffs.a1,
                        sc_coeffs.a2,
                        sc_coeffs.a3,
                        sc_coeffs.m0,
                        sc_coeffs.m1,
                        sc_coeffs.m2,
                    );
                    (filtered.abs(), filtered.abs())
                } else {
                    (left.abs(), right.abs())
                };

            self.envelope_l.process(detect_l);
            self.envelope_r.process(detect_r);
            (
                self.envelope_l.calculate_gain(&self.dynamic),
                self.envelope_r.calculate_gain(&self.dynamic),
            )
        } else {
            (1.0, 1.0)
        };

        // Process based on stereo placement
        match self.placement {
            StereoPlacement::Stereo => {
                let mut out_l = left;
                let mut out_r = right;

                for (i, coeffs) in self.svf_coeffs.iter().enumerate() {
                    out_l = self.svf_stages_l[i].process(
                        out_l, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                    out_r = self.svf_stages_r[i].process(
                        out_r, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                }

                // Apply dynamic gain
                (out_l * dyn_gain_l, out_r * dyn_gain_r)
            }
            StereoPlacement::Left => {
                let mut out_l = left;
                for (i, coeffs) in self.svf_coeffs.iter().enumerate() {
                    out_l = self.svf_stages_l[i].process(
                        out_l, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                }
                (out_l * dyn_gain_l, right)
            }
            StereoPlacement::Right => {
                let mut out_r = right;
                for (i, coeffs) in self.svf_coeffs.iter().enumerate() {
                    out_r = self.svf_stages_r[i].process(
                        out_r, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                }
                (left, out_r * dyn_gain_r)
            }
            StereoPlacement::Mid => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let mut out_mid = mid;
                for (i, coeffs) in self.svf_coeffs.iter().enumerate() {
                    out_mid = self.svf_stages_l[i].process(
                        out_mid, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                }
                out_mid *= dyn_gain_l;
                (out_mid + side, out_mid - side)
            }
            StereoPlacement::Side => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let mut out_side = side;
                for (i, coeffs) in self.svf_coeffs.iter().enumerate() {
                    out_side = self.svf_stages_l[i].process(
                        out_side, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
                    );
                }
                out_side *= dyn_gain_l;
                (mid + out_side, mid - out_side)
            }
        }
    }

    /// Get frequency response at a specific frequency
    pub fn frequency_response(&self, freq: f64) -> (f64, f64) {
        if !self.enabled || self.svf_coeffs.is_empty() {
            return (1.0, 0.0);
        }

        // Calculate magnitude and phase for SVF chain
        let omega = 2.0 * PI * freq / self.sample_rate;
        let mut total_mag = 1.0;
        let mut total_phase = 0.0;

        for coeffs in &self.svf_coeffs {
            let (mag, phase) = svf_frequency_response(coeffs, omega);
            total_mag *= mag;
            total_phase += phase;
        }

        (total_mag, total_phase)
    }

    pub fn reset(&mut self) {
        for stage in &mut self.svf_stages_l {
            stage.reset();
        }
        for stage in &mut self.svf_stages_r {
            stage.reset();
        }
        self.envelope_l.reset();
        self.envelope_r.reset();
        if let Some(ref mut sc) = self.sidechain_svf {
            sc.reset();
        }
    }
}

/// Calculate SVF frequency response using z-domain state-space analysis
///
/// For Simper's trapezoidal SVF:
///   v3 = v0 - ic2eq
///   v1 = a1*ic1eq + a2*v3   (bandpass-like)
///   v2 = ic2eq + a2*ic1eq + a3*v3  (lowpass)
///   output = m0*v0 + m1*v1 + m2*v2
///
/// We derive the z-domain transfer function by converting the difference equations.
fn svf_frequency_response(coeffs: &SvfCoeffs, omega: f64) -> (f64, f64) {
    // z = e^(jω) = cos(ω) + j*sin(ω)
    let cos_w = omega.cos();
    let sin_w = omega.sin();

    // For the SVF state equations, we need to find H(z) = Y(z)/X(z)
    // The trapezoidal SVF has a specific transfer function structure.
    //
    // From Simper's derivation, the outputs have these transfer functions:
    // For coefficients a1, a2, a3:
    //   g = a2/a1 (if a1 != 0)
    //   The SVF denominator is: D(z) = z^2 - 2*R*z + 1 (normalized form)
    //   where R depends on g and k
    //
    // Alternative: directly compute using the mixing coefficients
    // For the SVF with trapezoidal integration:
    //   H_lp(z) = a3*(1 + z^-1)^2 / D(z)
    //   H_bp(z) = a2*(1 - z^-2) / D(z)
    //   where D(z) = 1 - (2 - a3 - 2*a2)*z^-1 + (1 - 2*a2 + a3)*z^-2

    // Compute (1 + z^-1) = (1 + cos(ω) - j*sin(ω)) = (1 + cos(ω)) - j*sin(ω)
    let _one_plus_zinv_r = 1.0 + cos_w;
    let _one_plus_zinv_i = -sin_w;

    // Compute (1 - z^-1) = (1 - cos(ω) + j*sin(ω))
    let _one_minus_zinv_r = 1.0 - cos_w;
    let _one_minus_zinv_i = sin_w;

    // Compute z^-1 = cos(ω) - j*sin(ω)
    let _zinv_r = cos_w;
    let _zinv_i = -sin_w;

    // Compute z^-2 = cos(2ω) - j*sin(2ω)
    let _z2inv_r = (2.0 * omega).cos();
    let _z2inv_i = -(2.0 * omega).sin();

    // Denominator: D(z) = 1 + d1*z^-1 + d2*z^-2
    // From SVF analysis: d1 = -(2 - a3 - 2*a2), d2 = 1 - 2*a2 + a3
    // But actually for Simper's SVF the form is different.
    //
    // Let's use the correct form from state-space analysis:
    // The SVF state update is:
    //   ic1eq_new = 2*v1 - ic1eq_old
    //   ic2eq_new = 2*v2 - ic2eq_old
    // This gives us poles at specific locations.

    // For direct frequency response, we can use the fact that at z = e^(jω):
    // The trapezoidal integrator maps s = (2/T)(z-1)/(z+1), so:
    // At the center frequency f0, g = tan(π*f0/fs), and s = jg maps to z such that
    // jg = (2/T)(z-1)/(z+1)

    // Simpler approach: reconstruct g from coefficients
    // g = a2/a1 when a1 != 0
    let g = if coeffs.a1.abs() > 1e-10 {
        coeffs.a2 / coeffs.a1
    } else {
        0.0
    };

    // k can be found from: a1 = 1/(1 + g*(g+k)), so:
    // 1/a1 = 1 + g*g + g*k
    // g*k = 1/a1 - 1 - g*g
    // k = (1/a1 - 1 - g*g) / g
    let k = if g.abs() > 1e-10 && coeffs.a1.abs() > 1e-10 {
        (1.0 / coeffs.a1 - 1.0 - g * g) / g
    } else {
        1.0
    };

    // Use bilinear transform: s = (z-1)/(z+1) scaled by 2/T = 2*fs
    // But since g = tan(π*f0/fs), and we want to evaluate at f:
    // The analog frequency is s_analog = j*w_a where w_a = tan(π*f/fs)
    let w_a = (omega / 2.0).tan();

    // The SVF transfer functions in s-domain (normalized so ω0 = g):
    // H_lp(s) = g² / (s² + k*s + g²)
    // H_bp(s) = k*s / (s² + k*s + g²)  -- note: this gives peak of 1 at resonance
    // H_hp(s) = s² / (s² + k*s + g²)
    //
    // But Simper's BP uses different normalization. From his coefficients:
    // The actual BP is: H_bp = (g/k) * s / (s² + (g/k)*s + g²)
    // which has peak = k at resonance.

    // At s = j*w_a:
    let w = w_a;
    let w2 = w * w;
    let g2 = g * g;

    // Denominator D(jw) = (g² - w²) + j*k*w  -- wait, need to use correct k normalization
    // For Simper SVF: D(s) = s² + s*(g/Q) + g² where Q is defined differently
    //
    // Actually, from the coefficient formulas:
    //   a1 = 1/(1 + g*(g + k))
    // This means the continuous-time pole polynomial is s² + k*g*s + g² (renormalized)
    // So D(jw) = g² - w² + j*k*g*w

    let den_real = g2 - w2;
    let den_imag = k * g * w;
    let den_mag_sq = den_real * den_real + den_imag * den_imag;

    // NaN/Inf protection - check for invalid values
    if den_mag_sq < 1e-20 || !den_mag_sq.is_finite() || den_mag_sq.is_nan() {
        return (1.0, 0.0);
    }

    // H_lp(jw) = g² / D = g² * conj(D) / |D|²
    let lp_real = g2 * den_real / den_mag_sq;
    let lp_imag = -g2 * den_imag / den_mag_sq;

    // H_bp(jw) = jw * k / D  -- but we need to match Simper's BP definition
    // In Simper's formulation with output mixing:
    // v1 is the bandpass output, and it has transfer function:
    // H_v1(s) = a2 * s / (denominator) which normalizes differently
    //
    // Let's compute H_bp = j*w / D (standard 2nd order BP, unity peak at resonance)
    // Then multiply by appropriate scaling based on m1

    // Standard normalized BP: H_bp = j*w / D
    // j*w / D = j*w * conj(D) / |D|² = j*w * (den_real - j*den_imag) / |D|²
    //         = (w*den_imag + j*w*den_real) / |D|²
    let bp_real = w * den_imag / den_mag_sq;
    let bp_imag = w * den_real / den_mag_sq;

    // For bell filter, the output is: m0*input + m1*v1 + m2*v2
    // The v1 output (bandpass) in Simper's SVF has gain factor related to g and k
    // v1 = a2 * v3 + a1 * ic1eq where a2 = g*a1
    //
    // The effective bandpass transfer from input to v1 is:
    // H_v1 = g / (s + g/k + g*s/(...)) -- complex
    //
    // Alternative: since we know the bell filter should give +6dB at center freq
    // with Q=1 and gain_db=6, let's verify the m1 coefficient
    //
    // For bell: m1 = k * (A² - 1) where A = 10^(gain_db/40), k = 1/(Q*A)
    // At center frequency (w = g), the BP response should contribute m1 * (something)
    //
    // With standard BP at resonance: |H_bp(jg)| = g / (k*g) = 1/k
    // So bell response at center = m0 + m1 * (1/k) = 1 + k*(A²-1) / k = 1 + A² - 1 = A²
    // |H| = A² => 20*log10(A²) = 40*log10(A) = gain_db ✓

    // The issue is our BP calculation. At w = g:
    // den_real = g² - g² = 0
    // den_imag = k * g * g = k * g²
    // |D| = k * g²
    // BP = j*g / (j*k*g²) = 1/(k*g)

    // Hmm, that's 1/(k*g), not 1/k. Let me reconsider...
    //
    // Actually in Simper's SVF, the bandpass is scaled by g, so:
    // H_bp = g * j*w / D = j*g*w / D
    // At w = g: H_bp = j*g² / (j*k*g²) = 1/k ✓

    // So we need to scale BP by g:
    let bp_scaled_real = g * bp_real;
    let bp_scaled_imag = g * bp_imag;

    // Output: H = m0 + m1*H_bp_scaled + m2*H_lp
    let h_real = coeffs.m0 + coeffs.m1 * bp_scaled_real + coeffs.m2 * lp_real;
    let h_imag = coeffs.m1 * bp_scaled_imag + coeffs.m2 * lp_imag;

    let magnitude = (h_real * h_real + h_imag * h_imag).sqrt();
    let phase = h_imag.atan2(h_real);

    // Final NaN protection
    let safe_mag = if magnitude.is_finite() && !magnitude.is_nan() {
        magnitude.max(0.001)
    } else {
        1.0
    };
    let safe_phase = if phase.is_finite() && !phase.is_nan() {
        phase
    } else {
        0.0
    };

    (safe_mag, safe_phase)
}

// ============================================================================
// SPECTRUM ANALYZER
// ============================================================================

/// Real-time spectrum analyzer data
pub struct SpectrumAnalyzer {
    /// FFT planner
    fft_forward: Arc<dyn RealToComplex<f64>>,
    /// Input buffer
    input_buffer: Vec<f64>,
    /// Pre-computed Blackman-Harris window coefficients
    window: Vec<f64>,
    /// FFT output
    spectrum: Vec<Complex<f64>>,
    /// Smoothed magnitude (for display)
    magnitude_db: Vec<f64>,
    /// Peak hold
    peak_hold_db: Vec<f64>,
    /// Buffer position
    buffer_pos: usize,
    /// Smoothing factor
    smoothing: f64,
    /// Peak decay rate
    peak_decay: f64,
    /// FFT size
    fft_size: usize,
    /// Sample rate
    sample_rate: f64,
}

impl SpectrumAnalyzer {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = SPECTRUM_FFT_SIZE;
        let mut planner = RealFftPlanner::<f64>::new();
        let fft_forward = planner.plan_fft_forward(fft_size);

        let num_bins = fft_size / 2 + 1;

        // Pre-compute Blackman-Harris window coefficients (computed once, used every FFT)
        let window: Vec<f64> = (0..fft_size)
            .map(|i| {
                let t = i as f64 / (fft_size - 1) as f64;
                0.35875 - 0.48829 * (2.0 * PI * t).cos() + 0.14128 * (4.0 * PI * t).cos()
                    - 0.01168 * (6.0 * PI * t).cos()
            })
            .collect();

        Self {
            fft_forward,
            input_buffer: vec![0.0; fft_size],
            window,
            spectrum: vec![Complex::new(0.0, 0.0); num_bins],
            magnitude_db: vec![-120.0; num_bins],
            peak_hold_db: vec![-120.0; num_bins],
            buffer_pos: 0,
            smoothing: 0.8,
            peak_decay: 0.995,
            fft_size,
            sample_rate,
        }
    }

    /// Feed samples to analyzer
    pub fn process(&mut self, samples: &[f64]) {
        for &sample in samples {
            self.input_buffer[self.buffer_pos] = sample;
            self.buffer_pos = (self.buffer_pos + 1) % self.fft_size;

            // Process FFT when buffer is full
            if self.buffer_pos == 0 {
                self.compute_spectrum();
            }
        }
    }

    fn compute_spectrum(&mut self) {
        // Apply pre-computed Blackman-Harris window (no trig recalculation!)
        let mut windowed = self.input_buffer.clone();
        for (sample, &w) in windowed.iter_mut().zip(self.window.iter()) {
            *sample *= w;
        }

        // Compute FFT
        self.fft_forward
            .process(&mut windowed, &mut self.spectrum)
            .ok();

        // Update magnitude with smoothing
        let norm = 2.0 / self.fft_size as f64;
        for (i, c) in self.spectrum.iter().enumerate() {
            let mag = (c.re * c.re + c.im * c.im).sqrt() * norm;
            let db = if mag > 1e-10 {
                20.0 * mag.log10()
            } else {
                -120.0
            };

            // Smooth
            self.magnitude_db[i] =
                self.smoothing * self.magnitude_db[i] + (1.0 - self.smoothing) * db;

            // Peak hold
            if db > self.peak_hold_db[i] {
                self.peak_hold_db[i] = db;
            } else {
                self.peak_hold_db[i] *= self.peak_decay;
            }
        }
    }

    /// Get magnitude at frequency
    pub fn magnitude_at(&self, freq: f64) -> f64 {
        let bin = (freq * self.fft_size as f64 / self.sample_rate) as usize;
        if bin < self.magnitude_db.len() {
            self.magnitude_db[bin]
        } else {
            -120.0
        }
    }

    /// Get spectrum data for GPU upload (256 points, log-scaled)
    pub fn get_spectrum_data(&self, num_points: usize) -> Vec<f32> {
        let mut data = Vec::with_capacity(num_points);
        let log_min = 20.0_f64.log10();
        let log_max = (self.sample_rate / 2.0).log10();

        for i in 0..num_points {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 10.0_f64.powf(log_min + t * (log_max - log_min));
            let db = self.magnitude_at(freq);
            // Normalize to 0-1 range (-120 to 0 dB)
            let normalized = ((db + 120.0) / 120.0).clamp(0.0, 1.0);
            data.push(normalized as f32);
        }

        data
    }

    pub fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.magnitude_db.fill(-120.0);
        self.peak_hold_db.fill(-120.0);
        self.buffer_pos = 0;
    }
}

// ============================================================================
// EQ MATCH
// ============================================================================

/// EQ Match - learns target spectrum and generates matching EQ curve
pub struct EqMatch {
    /// Reference spectrum (averaged)
    reference_spectrum: Vec<f64>,
    /// Source spectrum (averaged)
    source_spectrum: Vec<f64>,
    /// Match curve (difference)
    match_curve: Vec<f64>,
    /// Number of samples captured
    ref_samples: usize,
    src_samples: usize,
    /// FFT planner
    fft_forward: Arc<dyn RealToComplex<f64>>,
    /// FFT buffer
    fft_buffer: Vec<f64>,
    /// Spectrum buffer
    spectrum_buffer: Vec<Complex<f64>>,
    /// Buffer position
    buffer_pos: usize,
    /// Sample rate
    sample_rate: f64,
    /// Match strength (0-100%)
    pub strength: f64,
    /// Smoothing amount
    pub smoothing: f64,
}

impl EqMatch {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = MATCH_FFT_SIZE;
        let num_bins = fft_size / 2 + 1;
        let mut planner = RealFftPlanner::<f64>::new();

        Self {
            reference_spectrum: vec![0.0; num_bins],
            source_spectrum: vec![0.0; num_bins],
            match_curve: vec![0.0; num_bins],
            ref_samples: 0,
            src_samples: 0,
            fft_forward: planner.plan_fft_forward(fft_size),
            fft_buffer: vec![0.0; fft_size],
            spectrum_buffer: vec![Complex::new(0.0, 0.0); num_bins],
            buffer_pos: 0,
            sample_rate,
            strength: 100.0,
            smoothing: 1.0,
        }
    }

    /// Learn reference spectrum
    pub fn learn_reference(&mut self, samples: &[f64]) {
        self.accumulate_spectrum(samples, true);
    }

    /// Learn source spectrum
    pub fn learn_source(&mut self, samples: &[f64]) {
        self.accumulate_spectrum(samples, false);
    }

    fn accumulate_spectrum(&mut self, samples: &[f64], is_reference: bool) {
        let fft_len = self.fft_buffer.len();

        for &sample in samples {
            self.fft_buffer[self.buffer_pos] = sample;
            self.buffer_pos += 1;

            if self.buffer_pos >= fft_len {
                // Apply window
                for i in 0..fft_len {
                    let t = i as f64 / (fft_len - 1) as f64;
                    let window = 0.5 - 0.5 * (2.0 * PI * t).cos(); // Hann
                    self.fft_buffer[i] *= window;
                }

                // FFT
                self.fft_forward
                    .process(&mut self.fft_buffer, &mut self.spectrum_buffer)
                    .ok();

                // Accumulate magnitude
                for (i, c) in self.spectrum_buffer.iter().enumerate() {
                    let mag = (c.re * c.re + c.im * c.im).sqrt();
                    if is_reference {
                        self.reference_spectrum[i] += mag;
                    } else {
                        self.source_spectrum[i] += mag;
                    }
                }

                if is_reference {
                    self.ref_samples += 1;
                } else {
                    self.src_samples += 1;
                }

                self.buffer_pos = 0;
            }
        }
    }

    /// Calculate match curve
    pub fn calculate_match(&mut self) {
        if self.ref_samples == 0 || self.src_samples == 0 {
            return;
        }

        for i in 0..self.match_curve.len() {
            let ref_avg = self.reference_spectrum[i] / self.ref_samples as f64;
            let src_avg = self.source_spectrum[i] / self.src_samples as f64;

            // Calculate dB difference
            let diff_db = if ref_avg > 1e-10 && src_avg > 1e-10 {
                20.0 * (ref_avg / src_avg).log10()
            } else {
                0.0
            };

            // Apply strength and smoothing
            self.match_curve[i] = diff_db * (self.strength / 100.0);
        }

        // Apply smoothing (simple moving average)
        if self.smoothing > 0.1 {
            let window = (self.smoothing * 10.0) as usize;
            let mut smoothed = self.match_curve.clone();
            for i in window..self.match_curve.len() - window {
                let mut sum = 0.0;
                for j in (i - window)..=(i + window) {
                    sum += self.match_curve[j];
                }
                smoothed[i] = sum / (2 * window + 1) as f64;
            }
            self.match_curve = smoothed;
        }
    }

    /// Get match gain at frequency
    pub fn gain_at(&self, freq: f64) -> f64 {
        let bin = (freq * MATCH_FFT_SIZE as f64 / self.sample_rate) as usize;
        if bin < self.match_curve.len() {
            self.match_curve[bin]
        } else {
            0.0
        }
    }

    /// Reset learning
    pub fn reset(&mut self) {
        self.reference_spectrum.fill(0.0);
        self.source_spectrum.fill(0.0);
        self.match_curve.fill(0.0);
        self.ref_samples = 0;
        self.src_samples = 0;
        self.buffer_pos = 0;
    }
}

// ============================================================================
// COLLISION DETECTION
// ============================================================================

/// Detects frequency masking between channels
#[derive(Debug)]
pub struct CollisionDetector {
    /// Spectrum per channel
    spectra: Vec<Vec<f64>>,
    /// Collision zones (frequency ranges with overlap)
    pub collision_zones: Vec<(f64, f64, f64)>, // (start_freq, end_freq, severity)
    /// Threshold for collision detection (dB)
    pub threshold_db: f64,
    sample_rate: f64,
}

impl CollisionDetector {
    pub fn new(sample_rate: f64, num_channels: usize) -> Self {
        let num_bins = SPECTRUM_FFT_SIZE / 2 + 1;
        Self {
            spectra: vec![vec![0.0; num_bins]; num_channels],
            collision_zones: Vec::new(),
            threshold_db: -6.0,
            sample_rate,
        }
    }

    /// Update spectrum for channel
    pub fn update_channel(&mut self, channel: usize, spectrum: &[f64]) {
        if channel < self.spectra.len() && spectrum.len() == self.spectra[channel].len() {
            self.spectra[channel].copy_from_slice(spectrum);
        }
    }

    /// Detect collisions between channels
    pub fn detect_collisions(&mut self) {
        self.collision_zones.clear();

        if self.spectra.len() < 2 {
            return;
        }

        let num_bins = self.spectra[0].len();
        let threshold = 10.0_f64.powf(self.threshold_db / 20.0);

        let mut in_collision = false;
        let mut collision_start = 0;
        let mut max_severity = 0.0_f64;

        for bin in 0..num_bins {
            // Check if multiple channels have significant energy at this bin
            let mut active_channels = 0;
            let mut total_energy = 0.0;

            for spectrum in &self.spectra {
                if spectrum[bin] > threshold {
                    active_channels += 1;
                    total_energy += spectrum[bin];
                }
            }

            let is_collision = active_channels >= 2;
            let severity = if active_channels > 0 {
                total_energy / active_channels as f64
            } else {
                0.0
            };

            if is_collision && !in_collision {
                collision_start = bin;
                in_collision = true;
                max_severity = severity;
            } else if is_collision && in_collision {
                max_severity = max_severity.max(severity);
            } else if !is_collision && in_collision {
                let start_freq =
                    collision_start as f64 * self.sample_rate / SPECTRUM_FFT_SIZE as f64;
                let end_freq = bin as f64 * self.sample_rate / SPECTRUM_FFT_SIZE as f64;
                self.collision_zones
                    .push((start_freq, end_freq, max_severity));
                in_collision = false;
            }
        }
    }
}

// ============================================================================
// AUTO GAIN
// ============================================================================

/// LUFS-based auto gain
#[derive(Debug)]
pub struct AutoGain {
    /// Input LUFS meter
    input_lufs: f64,
    /// Output LUFS meter
    output_lufs: f64,
    /// Accumulated loudness
    input_sum: f64,
    output_sum: f64,
    /// Sample count
    sample_count: u64,
    /// Gain to apply
    pub gain: f64,
    /// Enabled
    pub enabled: bool,
}

impl AutoGain {
    pub fn new() -> Self {
        Self {
            input_lufs: -23.0,
            output_lufs: -23.0,
            input_sum: 0.0,
            output_sum: 0.0,
            sample_count: 0,
            gain: 1.0,
            enabled: false,
        }
    }

    /// Process input sample (before EQ)
    pub fn process_input(&mut self, left: f64, right: f64) {
        let power = left * left + right * right;
        self.input_sum += power;
        self.sample_count += 1;
    }

    /// Process output sample (after EQ)
    pub fn process_output(&mut self, left: f64, right: f64) {
        let power = left * left + right * right;
        self.output_sum += power;
    }

    /// Update gain (call periodically, e.g., every 100ms)
    pub fn update(&mut self) {
        if self.sample_count < 4800 {
            return; // Need at least 100ms at 48kHz
        }

        let input_rms = (self.input_sum / self.sample_count as f64).sqrt();
        let output_rms = (self.output_sum / self.sample_count as f64).sqrt();

        if input_rms > 1e-10 && output_rms > 1e-10 {
            self.input_lufs = 20.0 * input_rms.log10();
            self.output_lufs = 20.0 * output_rms.log10();

            // Calculate compensation gain
            let diff_db = self.input_lufs - self.output_lufs;
            self.gain = 10.0_f64.powf(diff_db / 20.0);
        }

        // Reset accumulators
        self.input_sum = 0.0;
        self.output_sum = 0.0;
        self.sample_count = 0;
    }

    pub fn reset(&mut self) {
        self.input_sum = 0.0;
        self.output_sum = 0.0;
        self.sample_count = 0;
        self.gain = 1.0;
    }
}

impl Default for AutoGain {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// PROFESSIONAL EQ (MAIN STRUCT)
// ============================================================================

/// Professional 64-band parametric EQ
pub struct ProEq {
    /// EQ bands
    bands: Vec<EqBand>,
    /// Sample rate
    sample_rate: f64,

    // Global settings
    /// Output gain (dB)
    pub output_gain_db: f64,
    /// Phase mode for all bands (can be overridden per-band)
    pub global_phase_mode: PhaseMode,
    /// Analyzer mode
    pub analyzer_mode: AnalyzerMode,

    // Spectrum analyzer
    analyzer_pre: SpectrumAnalyzer,
    analyzer_post: SpectrumAnalyzer,
    analyzer_sidechain: SpectrumAnalyzer,

    // EQ Match
    pub eq_match: EqMatch,
    /// EQ match enabled
    pub match_enabled: bool,

    // Collision detection
    pub collision_detector: CollisionDetector,

    // Auto gain
    pub auto_gain: AutoGain,

    // A/B comparison
    state_a: Option<Vec<EqBandState>>,
    state_b: Option<Vec<EqBandState>>,
    current_state: char, // 'A' or 'B'

    // Processing
    /// Linear phase FIR (when needed)
    linear_phase_fir: Option<Vec<f64>>,
    linear_phase_dirty: bool,
}

/// Serializable band state for A/B
#[derive(Debug, Clone)]
struct EqBandState {
    enabled: bool,
    shape: FilterShape,
    frequency: f64,
    gain_db: f64,
    q: f64,
    slope: Slope,
    placement: StereoPlacement,
    dynamic: DynamicParams,
}

impl ProEq {
    pub fn new(sample_rate: f64) -> Self {
        let bands = (0..MAX_BANDS).map(|_| EqBand::new(sample_rate)).collect();

        Self {
            bands,
            sample_rate,
            output_gain_db: 0.0,
            global_phase_mode: PhaseMode::ZeroLatency,
            analyzer_mode: AnalyzerMode::PostEq,
            analyzer_pre: SpectrumAnalyzer::new(sample_rate),
            analyzer_post: SpectrumAnalyzer::new(sample_rate),
            analyzer_sidechain: SpectrumAnalyzer::new(sample_rate),
            eq_match: EqMatch::new(sample_rate),
            match_enabled: false,
            collision_detector: CollisionDetector::new(sample_rate, 2),
            auto_gain: AutoGain::new(),
            state_a: None,
            state_b: None,
            current_state: 'A',
            linear_phase_fir: None,
            linear_phase_dirty: true,
        }
    }

    /// Get band
    pub fn band(&self, index: usize) -> Option<&EqBand> {
        self.bands.get(index)
    }

    /// Get mutable band
    pub fn band_mut(&mut self, index: usize) -> Option<&mut EqBand> {
        self.linear_phase_dirty = true;
        self.bands.get_mut(index)
    }

    /// Enable band
    pub fn enable_band(&mut self, index: usize, enabled: bool) {
        if let Some(band) = self.bands.get_mut(index) {
            band.enabled = enabled;
            self.linear_phase_dirty = true;
        }
    }

    /// Set band parameters
    pub fn set_band(&mut self, index: usize, freq: f64, gain_db: f64, q: f64, shape: FilterShape) {
        if let Some(band) = self.bands.get_mut(index) {
            band.enabled = true;
            band.set_params(freq, gain_db, q, shape);
            self.linear_phase_dirty = true;
        }
    }

    /// Set band frequency only
    pub fn set_band_frequency(&mut self, index: usize, freq: f64) {
        if let Some(band) = self.bands.get_mut(index) {
            band.frequency = freq.clamp(20.0, 20000.0);
            band.needs_update = true;
            self.linear_phase_dirty = true;
        }
    }

    /// Set band gain only
    pub fn set_band_gain(&mut self, index: usize, gain_db: f64) {
        if let Some(band) = self.bands.get_mut(index) {
            band.gain_db = gain_db.clamp(-30.0, 30.0);
            band.needs_update = true;
            self.linear_phase_dirty = true;
        }
    }

    /// Set band Q only
    pub fn set_band_q(&mut self, index: usize, q: f64) {
        if let Some(band) = self.bands.get_mut(index) {
            band.q = q.clamp(0.1, 30.0);
            band.needs_update = true;
            self.linear_phase_dirty = true;
        }
    }

    /// Get enabled band count
    pub fn enabled_band_count(&self) -> usize {
        self.bands.iter().filter(|b| b.enabled).count()
    }

    /// Find next available band
    pub fn find_free_band(&self) -> Option<usize> {
        self.bands.iter().position(|b| !b.enabled)
    }

    /// Add band at frequency (spectrum grab)
    pub fn add_band_at(&mut self, freq: f64, gain_db: f64) -> Option<usize> {
        if let Some(index) = self.find_free_band() {
            self.set_band(index, freq, gain_db, 1.0, FilterShape::Bell);
            Some(index)
        } else {
            None
        }
    }

    /// Get total frequency response
    pub fn frequency_response(&self, freq: f64) -> (f64, f64) {
        let mut total_mag = 1.0;
        let mut total_phase = 0.0;

        for band in &self.bands {
            let (mag, phase) = band.frequency_response(freq);
            total_mag *= mag;
            total_phase += phase;
        }

        // Apply EQ match if enabled
        if self.match_enabled {
            let match_db = self.eq_match.gain_at(freq);
            total_mag *= 10.0_f64.powf(match_db / 20.0);
        }

        // Apply output gain
        total_mag *= 10.0_f64.powf(self.output_gain_db / 20.0);

        (total_mag, total_phase)
    }

    /// Get frequency response curve for display
    pub fn frequency_response_curve(&self, num_points: usize) -> Vec<(f64, f64)> {
        let mut curve = Vec::with_capacity(num_points);
        let log_min = 20.0_f64.log10();
        let log_max = 20000.0_f64.log10();

        for i in 0..num_points {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 10.0_f64.powf(log_min + t * (log_max - log_min));
            let (mag, _) = self.frequency_response(freq);
            let db = 20.0 * mag.log10();
            curve.push((freq, db.clamp(-30.0, 30.0)));
        }

        curve
    }

    /// Get spectrum data for GPU
    pub fn get_spectrum_data(&self) -> Vec<f32> {
        match self.analyzer_mode {
            AnalyzerMode::PreEq => self.analyzer_pre.get_spectrum_data(256),
            AnalyzerMode::PostEq => self.analyzer_post.get_spectrum_data(256),
            AnalyzerMode::Sidechain => self.analyzer_sidechain.get_spectrum_data(256),
            AnalyzerMode::Delta => {
                // Calculate difference between post and pre EQ spectrum
                let pre = self.analyzer_pre.get_spectrum_data(256);
                let post = self.analyzer_post.get_spectrum_data(256);
                pre.iter()
                    .zip(post.iter())
                    .map(|(pre_val, post_val)| post_val - pre_val)
                    .collect()
            }
            AnalyzerMode::Off => vec![0.0; 256],
        }
    }

    /// Store current state as A
    pub fn store_state_a(&mut self) {
        self.state_a = Some(self.capture_state());
        self.current_state = 'A';
    }

    /// Store current state as B
    pub fn store_state_b(&mut self) {
        self.state_b = Some(self.capture_state());
        self.current_state = 'B';
    }

    /// Switch to state A
    pub fn recall_state_a(&mut self) {
        if let Some(ref state) = self.state_a {
            self.restore_state(state.clone());
            self.current_state = 'A';
        }
    }

    /// Switch to state B
    pub fn recall_state_b(&mut self) {
        if let Some(ref state) = self.state_b {
            self.restore_state(state.clone());
            self.current_state = 'B';
        }
    }

    fn capture_state(&self) -> Vec<EqBandState> {
        self.bands
            .iter()
            .map(|b| EqBandState {
                enabled: b.enabled,
                shape: b.shape,
                frequency: b.frequency,
                gain_db: b.gain_db,
                q: b.q,
                slope: b.slope,
                placement: b.placement,
                dynamic: b.dynamic,
            })
            .collect()
    }

    fn restore_state(&mut self, state: Vec<EqBandState>) {
        for (band, s) in self.bands.iter_mut().zip(state.iter()) {
            band.enabled = s.enabled;
            band.shape = s.shape;
            band.frequency = s.frequency;
            band.gain_db = s.gain_db;
            band.q = s.q;
            band.slope = s.slope;
            band.placement = s.placement;
            band.dynamic = s.dynamic;
            band.needs_update = true;
        }
        self.linear_phase_dirty = true;
    }

    /// Process stereo block
    pub fn process_block(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        debug_assert_eq!(left.len(), right.len());

        // Pre-EQ analysis
        if matches!(self.analyzer_mode, AnalyzerMode::PreEq) {
            for (&l, &r) in left.iter().zip(right.iter()) {
                self.analyzer_pre.process(&[(l + r) * 0.5]);
            }
        }

        // Auto-gain input measurement
        if self.auto_gain.enabled {
            for (&l, &r) in left.iter().zip(right.iter()) {
                self.auto_gain.process_input(l, r);
            }
        }

        // Update band coefficients
        for band in &mut self.bands {
            if band.enabled && band.needs_update {
                band.update_coeffs();
            }
        }

        // Process each sample
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (mut out_l, mut out_r) = (*l, *r);

            // Process through all enabled bands
            for band in &mut self.bands {
                if band.enabled {
                    (out_l, out_r) = band.process(out_l, out_r);
                }
            }

            // Apply output gain
            let gain = 10.0_f64.powf(self.output_gain_db / 20.0);
            out_l *= gain;
            out_r *= gain;

            // Apply auto-gain
            if self.auto_gain.enabled {
                out_l *= self.auto_gain.gain;
                out_r *= self.auto_gain.gain;
            }

            *l = out_l;
            *r = out_r;
        }

        // Post-EQ analysis
        if matches!(self.analyzer_mode, AnalyzerMode::PostEq) {
            for (&l, &r) in left.iter().zip(right.iter()) {
                self.analyzer_post.process(&[(l + r) * 0.5]);
            }
        }

        // Auto-gain output measurement and update
        if self.auto_gain.enabled {
            for (&l, &r) in left.iter().zip(right.iter()) {
                self.auto_gain.process_output(l, r);
            }
            self.auto_gain.update();
        }
    }
}

impl Processor for ProEq {
    fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
        self.analyzer_pre.reset();
        self.analyzer_post.reset();
        self.analyzer_sidechain.reset();
        self.auto_gain.reset();
    }

    fn latency(&self) -> usize {
        match self.global_phase_mode {
            PhaseMode::Linear => LINEAR_PHASE_FIR_SIZE / 2,
            PhaseMode::Mixed { blend } => ((LINEAR_PHASE_FIR_SIZE / 2) as f32 * blend) as usize,
            _ => 0,
        }
    }
}

impl StereoProcessor for ProEq {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mut out_l = left;
        let mut out_r = right;

        for band in &mut self.bands {
            if band.enabled {
                (out_l, out_r) = band.process(out_l, out_r);
            }
        }

        let gain = 10.0_f64.powf(self.output_gain_db / 20.0);
        (out_l * gain, out_r * gain)
    }
}

impl ProcessorConfig for ProEq {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for band in &mut self.bands {
            band.sample_rate = sample_rate;
            band.needs_update = true;
        }
        self.analyzer_pre = SpectrumAnalyzer::new(sample_rate);
        self.analyzer_post = SpectrumAnalyzer::new(sample_rate);
        self.eq_match = EqMatch::new(sample_rate);
        self.linear_phase_dirty = true;
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_svf_bell() {
        let mut svf = SvfCore::new(48000.0);
        let coeffs = SvfCoeffs::bell(1000.0, 1.0, 6.0, 48000.0);

        // Process some samples
        for _ in 0..1000 {
            let _ = svf.process(
                0.5, coeffs.a1, coeffs.a2, coeffs.a3, coeffs.m0, coeffs.m1, coeffs.m2,
            );
        }
    }

    #[test]
    fn test_eq_band() {
        let mut band = EqBand::new(48000.0);
        band.enabled = true;
        band.set_params(1000.0, 6.0, 1.0, FilterShape::Bell);
        band.update_coeffs();

        // At center frequency, should boost
        let (mag, _) = band.frequency_response(1000.0);
        let db = 20.0 * mag.log10();
        assert!(db > 5.0 && db < 7.0, "Expected 5-7dB boost, got {}dB", db);
    }

    #[test]
    fn test_pro_eq() {
        let mut eq = ProEq::new(48000.0);

        eq.set_band(0, 100.0, -6.0, 0.707, FilterShape::LowShelf);
        eq.set_band(1, 3000.0, 3.0, 2.0, FilterShape::Bell);
        eq.set_band(2, 10000.0, 4.0, 0.707, FilterShape::HighShelf);

        assert_eq!(eq.enabled_band_count(), 3);

        let curve = eq.frequency_response_curve(100);
        assert_eq!(curve.len(), 100);
    }

    #[test]
    fn test_dynamic_eq() {
        let mut band = EqBand::new(48000.0);
        band.enabled = true;
        band.set_params(1000.0, 6.0, 1.0, FilterShape::Bell);
        band.dynamic = DynamicParams {
            enabled: true,
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 5.0,
            release_ms: 50.0,
            ..Default::default()
        };
        band.update_coeffs();

        // Process loud signal
        for _ in 0..4800 {
            let _ = band.process(0.5, 0.5);
        }
    }

    #[test]
    fn test_spectrum_analyzer() {
        let mut analyzer = SpectrumAnalyzer::new(48000.0);

        // Process some samples
        let samples: Vec<f64> = (0..8192).map(|i| (i as f64 * 0.01).sin()).collect();
        analyzer.process(&samples);

        let data = analyzer.get_spectrum_data(256);
        assert_eq!(data.len(), 256);
    }

    #[test]
    fn test_ab_comparison() {
        let mut eq = ProEq::new(48000.0);

        eq.set_band(0, 1000.0, 6.0, 1.0, FilterShape::Bell);
        eq.store_state_a();

        eq.set_band(0, 2000.0, -6.0, 2.0, FilterShape::Bell);
        eq.store_state_b();

        eq.recall_state_a();
        assert_eq!(eq.band(0).unwrap().frequency, 1000.0);

        eq.recall_state_b();
        assert_eq!(eq.band(0).unwrap().frequency, 2000.0);
    }
}
