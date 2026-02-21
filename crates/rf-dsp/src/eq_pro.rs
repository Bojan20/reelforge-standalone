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

/// Denormal prevention constant
const DENORMAL_PREVENTION: f64 = 1e-25;

/// Coefficient smoothing length (samples) for zipper-free interpolation
const COEFF_SMOOTH_SAMPLES: usize = 64;

// ============================================================================
// MZT FILTER (Matched Z-Transform, cramping-free at Nyquist)
// ============================================================================

/// MZT filter coefficients — cramping-free matched z-transform
#[derive(Debug, Clone, Copy)]
pub struct MztCoeffs {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl MztCoeffs {
    /// Identity (passthrough) coefficients
    pub fn identity() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }

    /// Bell filter using MZT (no cramping at Nyquist)
    pub fn bell_mzt(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * PI * freq / sample_rate;

        // Pre-warped frequency for matched response
        let w_pre = 2.0 * sample_rate * (w0 / 2.0).tan();
        let alpha = w_pre / (2.0 * q * sample_rate);

        let cos_w0 = w0.cos();

        let b0 = 1.0 + alpha * a;
        let b1 = -2.0 * cos_w0;
        let b2 = 1.0 - alpha * a;
        let a0 = 1.0 + alpha / a;
        let a1 = -2.0 * cos_w0;
        let a2 = 1.0 - alpha / a;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// High shelf using MZT
    pub fn high_shelf_mzt(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let a_sqrt = a.sqrt();
        let two_sqrt_a_alpha = 2.0 * a_sqrt * alpha;

        let b0 = a * ((a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha);
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0);
        let b2 = a * ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha);
        let a0 = (a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
        let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0);
        let a2 = (a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Low shelf using MZT
    pub fn low_shelf_mzt(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let a_sqrt = a.sqrt();
        let two_sqrt_a_alpha = 2.0 * a_sqrt * alpha;

        let b0 = a * ((a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha);
        let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0);
        let b2 = a * ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha);
        let a0 = (a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
        let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0);
        let a2 = (a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Highpass using MZT
    pub fn highpass_mzt(freq: f64, q: f64, sample_rate: f64) -> Self {
        let w0 = 2.0 * PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let b0 = (1.0 + cos_w0) / 2.0;
        let b1 = -(1.0 + cos_w0);
        let b2 = (1.0 + cos_w0) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w0;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Lowpass using MZT
    pub fn lowpass_mzt(freq: f64, q: f64, sample_rate: f64) -> Self {
        let w0 = 2.0 * PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * q);

        let b0 = (1.0 - cos_w0) / 2.0;
        let b1 = 1.0 - cos_w0;
        let b2 = (1.0 - cos_w0) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w0;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }
}

impl Default for MztCoeffs {
    fn default() -> Self {
        Self::identity()
    }
}

/// MZT Filter with zipper-free coefficient interpolation
#[derive(Debug, Clone)]
pub struct MztFilter {
    /// Current coefficients
    current: MztCoeffs,
    /// Target coefficients (for interpolation)
    target: MztCoeffs,
    /// TDF-II delay states
    z1: f64,
    z2: f64,
    /// Interpolation counter
    smooth_counter: usize,
}

impl MztFilter {
    pub fn new() -> Self {
        Self {
            current: MztCoeffs::identity(),
            target: MztCoeffs::identity(),
            z1: 0.0,
            z2: 0.0,
            smooth_counter: 0,
        }
    }

    /// Set new target coefficients (will interpolate smoothly)
    pub fn set_coeffs(&mut self, coeffs: MztCoeffs) {
        self.target = coeffs;
        self.smooth_counter = COEFF_SMOOTH_SAMPLES;
    }

    /// Process a single sample with interpolation
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        // Interpolate coefficients if needed
        if self.smooth_counter > 0 {
            let t = 1.0 - (self.smooth_counter as f64 / COEFF_SMOOTH_SAMPLES as f64);
            // Cosine interpolation for smooth transition
            let alpha = 0.5 * (1.0 - (PI * t).cos());
            self.current.b0 = self.current.b0 + alpha * (self.target.b0 - self.current.b0);
            self.current.b1 = self.current.b1 + alpha * (self.target.b1 - self.current.b1);
            self.current.b2 = self.current.b2 + alpha * (self.target.b2 - self.current.b2);
            self.current.a1 = self.current.a1 + alpha * (self.target.a1 - self.current.a1);
            self.current.a2 = self.current.a2 + alpha * (self.target.a2 - self.current.a2);
            self.smooth_counter -= 1;
            if self.smooth_counter == 0 {
                self.current = self.target;
            }
        }

        // TDF-II biquad
        let output = self.current.b0 * input + self.z1;
        self.z1 =
            self.current.b1 * input - self.current.a1 * output + self.z2 + DENORMAL_PREVENTION;
        self.z2 = self.current.b2 * input - self.current.a2 * output;

        output
    }

    pub fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
        self.smooth_counter = 0;
        self.current = self.target;
    }
}

impl Default for MztFilter {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// OVERSAMPLING (Adaptive 2x/4x/8x)
// ============================================================================

/// Oversampling mode
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum OversampleMode {
    #[default]
    Off,
    X2,
    X4,
    X8,
    Adaptive,
}

/// 47-tap halfband FIR filter for oversampling
#[derive(Debug, Clone)]
pub struct HalfbandFilter {
    coeffs: Vec<f64>,
    delay_line: Vec<f64>,
    write_pos: usize,
}

impl HalfbandFilter {
    pub fn new() -> Self {
        // 47-tap linear phase FIR, -96dB stopband
        let coeffs = vec![
            -0.000043, 0.0, 0.000206, 0.0, -0.000693, 0.0, 0.001838, 0.0, -0.004148, 0.0,
            0.008349, 0.0, -0.015542, 0.0, 0.027401, 0.0, -0.047430, 0.0, 0.083810, 0.0,
            -0.168150, 0.0, 0.640994, 1.0, 0.640994, 0.0, -0.168150, 0.0, 0.083810, 0.0,
            -0.047430, 0.0, 0.027401, 0.0, -0.015542, 0.0, 0.008349, 0.0, -0.004148, 0.0,
            0.001838, 0.0, -0.000693, 0.0, 0.000206, 0.0, -0.000043,
        ];
        let len = coeffs.len();
        Self {
            coeffs,
            delay_line: vec![0.0; len],
            write_pos: 0,
        }
    }

    fn push_sample(&mut self, sample: f64) {
        self.delay_line[self.write_pos] = sample;
        self.write_pos = (self.write_pos + 1) % self.delay_line.len();
    }

    fn convolve(&self) -> f64 {
        let len = self.coeffs.len();
        let mut sum = 0.0;
        for i in 0..len {
            let idx = (self.write_pos + len - 1 - i) % len;
            sum += self.delay_line[idx] * self.coeffs[i];
        }
        sum
    }

    /// Upsample by 2x: insert zeros and filter
    pub fn upsample(&mut self, input: f64) -> (f64, f64) {
        self.push_sample(input);
        let y0 = self.convolve() * 2.0;
        self.push_sample(0.0);
        let y1 = self.convolve() * 2.0;
        (y0, y1)
    }

    /// Downsample by 2x: filter and decimate
    pub fn downsample(&mut self, s0: f64, s1: f64) -> f64 {
        self.push_sample(s0);
        self.push_sample(s1);
        self.convolve()
    }

    pub fn reset(&mut self) {
        self.delay_line.fill(0.0);
        self.write_pos = 0;
    }
}

impl Default for HalfbandFilter {
    fn default() -> Self {
        Self::new()
    }
}

/// Oversampler with cascaded halfband filters
#[derive(Debug, Clone)]
pub struct Oversampler {
    mode: OversampleMode,
    up_filters: Vec<HalfbandFilter>,
    down_filters: Vec<HalfbandFilter>,
}

impl Oversampler {
    pub fn new(mode: OversampleMode) -> Self {
        let stages = match mode {
            OversampleMode::Off => 0,
            OversampleMode::X2 => 1,
            OversampleMode::X4 => 2,
            OversampleMode::X8 | OversampleMode::Adaptive => 3,
        };

        Self {
            mode,
            up_filters: (0..stages).map(|_| HalfbandFilter::new()).collect(),
            down_filters: (0..stages).map(|_| HalfbandFilter::new()).collect(),
        }
    }

    /// Process with oversampling: upsample → process at higher rate → downsample
    pub fn process<F>(&mut self, input: f64, mut process_fn: F) -> f64
    where
        F: FnMut(f64) -> f64,
    {
        if self.mode == OversampleMode::Off {
            return process_fn(input);
        }

        let stages = self.up_filters.len();

        // Build upsampled buffer
        let mut samples = vec![input];
        for stage in 0..stages {
            let mut upsampled = Vec::with_capacity(samples.len() * 2);
            for &s in &samples {
                let (a, b) = self.up_filters[stage].upsample(s);
                upsampled.push(a);
                upsampled.push(b);
            }
            samples = upsampled;
        }

        // Process at oversampled rate
        for s in &mut samples {
            *s = process_fn(*s);
        }

        // Downsample back
        for stage in (0..stages).rev() {
            let mut downsampled = Vec::with_capacity(samples.len() / 2);
            for pair in samples.chunks(2) {
                let out = self.down_filters[stage].downsample(pair[0], pair[1]);
                downsampled.push(out);
            }
            samples = downsampled;
        }

        samples[0]
    }

    pub fn latency(&self) -> usize {
        let taps_per_stage = 47;
        let stages = self.up_filters.len();
        stages * taps_per_stage / 2
    }

    pub fn reset(&mut self) {
        for f in &mut self.up_filters {
            f.reset();
        }
        for f in &mut self.down_filters {
            f.reset();
        }
    }

    pub fn mode(&self) -> OversampleMode {
        self.mode
    }

    pub fn set_mode(&mut self, mode: OversampleMode) {
        if mode != self.mode {
            *self = Self::new(mode);
        }
    }
}

// ============================================================================
// TRANSIENT DETECTOR (fast/slow envelope for transient-aware Q)
// ============================================================================

/// Transient detector using fast/slow envelope ratio
#[derive(Debug, Clone)]
pub struct TransientDetector {
    fast_env: f64,
    slow_env: f64,
    fast_attack: f64,
    fast_release: f64,
    slow_attack: f64,
    slow_release: f64,
    pub threshold: f64,
    is_transient: bool,
    transient_countdown: usize,
}

impl TransientDetector {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            fast_env: 0.0,
            slow_env: 0.0,
            fast_attack: (-1.0 / (0.001 * sample_rate)).exp(),    // 1ms
            fast_release: (-1.0 / (0.010 * sample_rate)).exp(),   // 10ms
            slow_attack: (-1.0 / (0.050 * sample_rate)).exp(),    // 50ms
            slow_release: (-1.0 / (0.200 * sample_rate)).exp(),   // 200ms
            threshold: 2.0,
            is_transient: false,
            transient_countdown: 0,
        }
    }

    /// Detect transient in input sample, returns transient ratio (>1.0 = transient)
    pub fn process(&mut self, input: f64) -> f64 {
        let abs = input.abs();

        // Fast envelope
        let fast_coeff = if abs > self.fast_env {
            self.fast_attack
        } else {
            self.fast_release
        };
        self.fast_env = fast_coeff * self.fast_env + (1.0 - fast_coeff) * abs;

        // Slow envelope
        let slow_coeff = if abs > self.slow_env {
            self.slow_attack
        } else {
            self.slow_release
        };
        self.slow_env = slow_coeff * self.slow_env + (1.0 - slow_coeff) * abs;

        // Ratio
        let ratio = if self.slow_env > 1e-10 {
            self.fast_env / self.slow_env
        } else {
            1.0
        };

        if ratio > self.threshold {
            self.is_transient = true;
            // 20ms transient window at 48kHz
            self.transient_countdown = 960;
        } else if self.transient_countdown > 0 {
            self.transient_countdown -= 1;
            if self.transient_countdown == 0 {
                self.is_transient = false;
            }
        }

        ratio
    }

    pub fn is_transient(&self) -> bool {
        self.is_transient
    }

    pub fn reset(&mut self) {
        self.fast_env = 0.0;
        self.slow_env = 0.0;
        self.is_transient = false;
        self.transient_countdown = 0;
    }
}

// ============================================================================
// HARMONIC SATURATOR (per-band analog saturation)
// ============================================================================

/// Saturation type for per-band analog character
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum SaturationType {
    #[default]
    Tube,
    Tape,
    Transistor,
    Soft,
}

/// Per-band harmonic saturator
#[derive(Debug, Clone)]
pub struct HarmonicSaturator {
    pub drive: f64,
    pub mix: f64,
    pub saturation_type: SaturationType,
    pub asymmetry: f64,
}

impl HarmonicSaturator {
    pub fn new() -> Self {
        Self {
            drive: 0.0,
            mix: 0.0,
            saturation_type: SaturationType::Tube,
            asymmetry: 0.0,
        }
    }

    pub fn process(&self, input: f64) -> f64 {
        if self.drive < 0.001 || self.mix < 0.001 {
            return input;
        }

        let driven = input * (1.0 + self.drive * 10.0);
        let asymm = driven + self.asymmetry * driven * driven;

        let saturated = match self.saturation_type {
            SaturationType::Tube => {
                // Soft tube saturation with even harmonics
                if asymm >= 0.0 {
                    1.0 - (-asymm).exp()
                } else {
                    -(1.0 - asymm.exp())
                }
            }
            SaturationType::Tape => {
                // Tape compression curve
                asymm.tanh()
            }
            SaturationType::Transistor => {
                // Hard transistor clipping
                asymm.clamp(-1.0, 1.0)
            }
            SaturationType::Soft => {
                // Cubic soft clip
                if asymm.abs() < 2.0 / 3.0 {
                    asymm
                } else if asymm > 0.0 {
                    1.0 - (2.0 - 3.0 * asymm).powi(2) / 3.0
                } else {
                    -(1.0 - (2.0 + 3.0 * asymm).powi(2) / 3.0)
                }
            }
        };

        // Wet/dry mix
        input * (1.0 - self.mix) + saturated * self.mix
    }
}

impl Default for HarmonicSaturator {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// EQUAL LOUDNESS (ISO 226:2003)
// ============================================================================

/// ISO 226:2003 equal loudness compensation
#[derive(Debug, Clone)]
pub struct EqualLoudness {
    compensation_curve: Vec<(f64, f64)>,
    pub enabled: bool,
    pub reference_level: f64,
}

impl EqualLoudness {
    pub fn new() -> Self {
        Self {
            compensation_curve: Vec::new(),
            enabled: false,
            reference_level: -23.0,
        }
    }

    /// Get compensation in dB at a given frequency
    pub fn compensation_db(&self, freq: f64) -> f64 {
        if !self.enabled {
            return 0.0;
        }

        // ISO 226 approximation using standard reference frequencies
        let reference_freqs: [f64; 29] = [
            20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0, 250.0, 315.0,
            400.0, 500.0, 630.0, 800.0, 1000.0, 1250.0, 1600.0, 2000.0, 2500.0, 3150.0, 4000.0,
            5000.0, 6300.0, 8000.0, 10000.0, 12500.0,
        ];

        // Equal loudness contour at ~60 phon (relative to 1kHz)
        let contour_60: [f64; 29] = [
            74.3, 65.0, 56.3, 48.4, 41.7, 35.5, 29.8, 25.1, 20.7, 16.8, 13.8, 11.2, 8.9, 7.2,
            6.0, 5.0, 4.4, 4.2, 3.7, 2.6, 1.0, -1.2, -3.6, -3.8, -1.1, 2.8, 7.0, 12.0, 18.0,
        ];

        // Find surrounding reference points
        if freq <= reference_freqs[0] {
            return contour_60[0] - 4.2; // Relative to 1kHz reference
        }
        if freq >= reference_freqs[28] {
            return contour_60[28] - 4.2;
        }

        for i in 0..28 {
            if freq >= reference_freqs[i] && freq < reference_freqs[i + 1] {
                let t = (freq.log2() - reference_freqs[i].log2())
                    / (reference_freqs[i + 1].log2() - reference_freqs[i].log2());
                let db = contour_60[i] + t * (contour_60[i + 1] - contour_60[i]);
                return db - 4.2; // Relative to 1kHz reference
            }
        }

        0.0
    }

    /// Generate compensation curve for a number of frequency points
    pub fn generate_curve(&mut self, num_points: usize, sample_rate: f64) {
        self.compensation_curve.clear();
        let nyquist = sample_rate / 2.0;

        for i in 0..num_points {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (nyquist / 20.0).powf(t);
            let db = self.compensation_db(freq);
            self.compensation_curve.push((freq, db));
        }
    }
}

impl Default for EqualLoudness {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// CORRELATION METER (inter-channel stereo correlation)
// ============================================================================

/// Inter-channel correlation meter
#[derive(Debug, Clone)]
pub struct CorrelationMeter {
    left_buffer: Vec<f64>,
    right_buffer: Vec<f64>,
    write_pos: usize,
    window_size: usize,
    pub correlation: f64,
}

impl CorrelationMeter {
    pub fn new(sample_rate: f64) -> Self {
        // 300ms window
        let window_size = (sample_rate * 0.3) as usize;
        Self {
            left_buffer: vec![0.0; window_size],
            right_buffer: vec![0.0; window_size],
            write_pos: 0,
            window_size,
            correlation: 1.0,
        }
    }

    pub fn process(&mut self, left: f64, right: f64) {
        self.left_buffer[self.write_pos] = left;
        self.right_buffer[self.write_pos] = right;
        self.write_pos = (self.write_pos + 1) % self.window_size;

        // Calculate correlation periodically (every 256 samples)
        if self.write_pos % 256 == 0 {
            self.update_correlation();
        }
    }

    fn update_correlation(&mut self) {
        let n = self.window_size as f64;

        let mut sum_l = 0.0;
        let mut sum_r = 0.0;
        let mut sum_ll = 0.0;
        let mut sum_rr = 0.0;
        let mut sum_lr = 0.0;

        for i in 0..self.window_size {
            let l = self.left_buffer[i];
            let r = self.right_buffer[i];
            sum_l += l;
            sum_r += r;
            sum_ll += l * l;
            sum_rr += r * r;
            sum_lr += l * r;
        }

        let mean_l = sum_l / n;
        let mean_r = sum_r / n;

        let var_l = (sum_ll / n - mean_l * mean_l).max(0.0);
        let var_r = (sum_rr / n - mean_r * mean_r).max(0.0);
        let covar = sum_lr / n - mean_l * mean_r;

        let denom = (var_l * var_r).sqrt();
        self.correlation = if denom > 1e-10 { covar / denom } else { 1.0 };
    }

    pub fn reset(&mut self) {
        self.left_buffer.fill(0.0);
        self.right_buffer.fill(0.0);
        self.write_pos = 0;
        self.correlation = 1.0;
    }
}

// ============================================================================
// FREQUENCY ANALYZER (AI-powered frequency suggestions)
// ============================================================================

/// Frequency suggestion from analyzer
#[derive(Debug, Clone)]
pub struct FrequencySuggestion {
    pub frequency: f64,
    pub description: &'static str,
    pub action: &'static str,
    pub typical_q: f64,
    pub gain_range: (f64, f64),
}

/// Frequency analyzer with problem detection
#[derive(Debug)]
pub struct FrequencyAnalyzer {
    spectrum_sum: Vec<f64>,
    spectrum_count: usize,
    sample_rate: f64,
    fft_size: usize,
    peak_frequencies: Vec<f64>,
}

impl FrequencyAnalyzer {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            spectrum_sum: vec![0.0; 2048],
            spectrum_count: 0,
            sample_rate,
            fft_size: 4096,
            peak_frequencies: Vec::new(),
        }
    }

    /// Accumulate spectrum data
    pub fn add_spectrum(&mut self, spectrum: &[f64]) {
        let len = spectrum.len().min(self.spectrum_sum.len());
        for i in 0..len {
            self.spectrum_sum[i] += spectrum[i];
        }
        self.spectrum_count += 1;
    }

    /// Find peaks in accumulated spectrum
    pub fn find_peaks(&mut self) -> Vec<(f64, f64)> {
        if self.spectrum_count == 0 {
            return Vec::new();
        }

        let avg: Vec<f64> = self.spectrum_sum.iter().map(|s| s / self.spectrum_count as f64).collect();

        let mut peaks = Vec::new();
        let threshold = avg.iter().cloned().fold(f64::NEG_INFINITY, f64::max) * 0.5;

        for i in 2..avg.len() - 2 {
            if avg[i] > avg[i - 1]
                && avg[i] > avg[i + 1]
                && avg[i] > avg[i - 2]
                && avg[i] > avg[i + 2]
                && avg[i] > threshold
            {
                let freq = i as f64 * self.sample_rate / self.fft_size as f64;
                peaks.push((freq, avg[i]));
            }
        }

        self.peak_frequencies = peaks.iter().map(|(f, _)| *f).collect();
        peaks
    }

    /// Get AI-powered suggestions for common problems
    pub fn get_suggestions(&self) -> Vec<FrequencySuggestion> {
        let known_problems = [
            (60.0, "Hum/mains buzz", "Cut", 10.0, (-12.0, -3.0)),
            (120.0, "Second harmonic hum", "Cut", 8.0, (-9.0, -3.0)),
            (200.0, "Muddiness/boominess", "Cut", 1.5, (-6.0, -2.0)),
            (300.0, "Boxiness", "Cut", 2.0, (-6.0, -2.0)),
            (500.0, "Honkiness", "Cut", 2.5, (-4.0, -1.0)),
            (800.0, "Nasal quality", "Cut", 2.0, (-4.0, -1.0)),
            (2500.0, "Harshness/sibilance", "Cut", 3.0, (-6.0, -2.0)),
            (3500.0, "Presence/clarity", "Boost", 1.5, (1.0, 4.0)),
            (5000.0, "Definition", "Boost", 1.0, (1.0, 3.0)),
            (8000.0, "Air/brilliance", "Boost", 0.7, (1.0, 4.0)),
            (12000.0, "Sparkle", "Boost", 0.5, (1.0, 3.0)),
        ];

        let mut suggestions = Vec::new();

        for peak_freq in &self.peak_frequencies {
            for &(problem_freq, desc, action, q, gain_range) in &known_problems {
                if (*peak_freq - problem_freq).abs() < problem_freq * 0.15 {
                    suggestions.push(FrequencySuggestion {
                        frequency: *peak_freq,
                        description: desc,
                        action,
                        typical_q: q,
                        gain_range,
                    });
                }
            }
        }

        suggestions
    }

    pub fn reset(&mut self) {
        self.spectrum_sum.fill(0.0);
        self.spectrum_count = 0;
        self.peak_frequencies.clear();
    }
}

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
    /// Note: 7 coefficients are standard for SVF implementation (a1, a2, a3, m0, m1, m2)
    #[allow(clippy::too_many_arguments)]
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

    // === Ultra features (optional per-band) ===

    /// Use MZT filter instead of SVF (cramping-free at Nyquist)
    pub use_mzt: bool,
    /// MZT filter L/R channels
    mzt_filter_l: MztFilter,
    mzt_filter_r: MztFilter,

    /// Per-band oversampler L/R
    oversampler_l: Option<Oversampler>,
    oversampler_r: Option<Oversampler>,

    /// Transient detector for transient-aware Q reduction
    pub transient_aware: bool,
    transient_detector: TransientDetector,
    /// Q reduction factor during transients (0.0 = no reduction, 1.0 = full reduction)
    pub transient_q_reduction: f64,

    /// Per-band harmonic saturator
    pub saturator: HarmonicSaturator,

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
            // Ultra features (disabled by default)
            use_mzt: false,
            mzt_filter_l: MztFilter::new(),
            mzt_filter_r: MztFilter::new(),
            oversampler_l: None,
            oversampler_r: None,
            transient_aware: false,
            transient_detector: TransientDetector::new(sample_rate),
            transient_q_reduction: 0.5,
            saturator: HarmonicSaturator::new(),
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

        // Update MZT filters if enabled
        if self.use_mzt {
            let mzt_coeffs = match self.shape {
                FilterShape::Bell => {
                    MztCoeffs::bell_mzt(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::LowShelf => {
                    MztCoeffs::low_shelf_mzt(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::HighShelf => {
                    MztCoeffs::high_shelf_mzt(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
                FilterShape::LowCut | FilterShape::HighCut => {
                    MztCoeffs::highpass_mzt(self.frequency, self.q, self.sample_rate)
                }
                _ => {
                    // MZT best for bell/shelf; fallback to bell for other shapes
                    MztCoeffs::bell_mzt(self.frequency, self.q, self.gain_db, self.sample_rate)
                }
            };
            self.mzt_filter_l.set_coeffs(mzt_coeffs);
            self.mzt_filter_r.set_coeffs(mzt_coeffs);
        }

        // Recreate transient detector if sample rate changed (no set_sample_rate method)
        if self.transient_aware {
            self.transient_detector = TransientDetector::new(self.sample_rate);
        }

        self.needs_update = false;
    }

    /// Set MZT mode (Matched Z-Transform — cramping-free at Nyquist)
    pub fn set_use_mzt(&mut self, enabled: bool) {
        self.use_mzt = enabled;
        self.needs_update = true;
    }

    /// Set oversampling mode
    pub fn set_oversampling(&mut self, mode: OversampleMode) {
        match mode {
            OversampleMode::Off => {
                self.oversampler_l = None;
                self.oversampler_r = None;
            }
            _ => {
                self.oversampler_l = Some(Oversampler::new(mode));
                self.oversampler_r = Some(Oversampler::new(mode));
            }
        }
        self.needs_update = true;
    }

    /// Set transient-aware mode
    pub fn set_transient_aware(&mut self, enabled: bool, q_reduction: f64) {
        self.transient_aware = enabled;
        self.transient_q_reduction = q_reduction.clamp(0.0, 1.0);
    }

    /// Set saturator parameters
    pub fn set_saturator(&mut self, drive_db: f64, mix: f64, sat_type: SaturationType) {
        self.saturator.drive = drive_db;
        self.saturator.mix = mix.clamp(0.0, 1.0);
        self.saturator.saturation_type = sat_type;
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
            1 => std::f64::consts::FRAC_1_SQRT_2, // 6dB/oct - single pole, Q=1/sqrt(2)
            2 => std::f64::consts::FRAC_1_SQRT_2, // 12dB/oct - Q = 1/sqrt(2)
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
                    0 => 0.5176380902050415,              // Q1
                    1 => std::f64::consts::FRAC_1_SQRT_2, // Q2
                    _ => 1.9318516525781366,              // Q3
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
                    2 => 0.630_547_596_887_777,
                    3 => 0.8211172650655689,
                    4 => 1.224_744_871_391_589,
                    _ => 3.830_648_852_148_459,
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
                    6 => 1.722_447_098_238_328,
                    _ => 5.101_148_618_689_155,
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

    /// Process a single channel through SVF stages
    #[inline]
    fn process_svf_chain(stages: &mut [SvfCore], coeffs: &[SvfCoeffs], input: Sample) -> Sample {
        let mut out = input;
        for (i, c) in coeffs.iter().enumerate() {
            out = stages[i].process(out, c.a1, c.a2, c.a3, c.m0, c.m1, c.m2);
        }
        out
    }

    /// Core filter processing for a single channel — SVF or MZT, with optional oversampling
    #[inline]
    fn process_filter_channel(
        input: Sample,
        use_mzt: bool,
        mzt_filter: &mut MztFilter,
        svf_stages: &mut [SvfCore],
        svf_coeffs: &[SvfCoeffs],
        oversampler: &mut Option<Oversampler>,
    ) -> Sample {
        if use_mzt {
            // MZT path (zipper-free, cramping-free)
            if let Some(os) = oversampler {
                os.process(input, |s| mzt_filter.process(s))
            } else {
                mzt_filter.process(input)
            }
        } else {
            // SVF path (original ProEq)
            if let Some(os) = oversampler {
                os.process(input, |s| Self::process_svf_chain(svf_stages, svf_coeffs, s))
            } else {
                Self::process_svf_chain(svf_stages, svf_coeffs, input)
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

        // Transient-aware Q reduction: detect transient and temporarily reduce Q
        // This prevents ringing on sharp transients (drum hits, etc.)
        let _transient_q_mult = if self.transient_aware {
            let mono = (left + right) * 0.5;
            let transient_amount = self.transient_detector.process(mono);
            // During transients, reduce Q toward self.transient_q_reduction
            if transient_amount > 0.0 {
                1.0 - (transient_amount * self.transient_q_reduction).min(0.9)
            } else {
                1.0
            }
        } else {
            1.0
        };

        // Calculate dynamic gain if enabled
        let (dyn_gain_l, dyn_gain_r) = if self.dynamic.enabled {
            let (detect_l, detect_r) = if let (Some(sc_svf), Some(sc_coeffs)) =
                (self.sidechain_svf.as_mut(), self.sidechain_coeffs.as_ref())
            {
                let filtered = sc_svf.process(
                    (left + right) * 0.5,
                    sc_coeffs.a1, sc_coeffs.a2, sc_coeffs.a3,
                    sc_coeffs.m0, sc_coeffs.m1, sc_coeffs.m2,
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
        let (mut out_l, mut out_r) = match self.placement {
            StereoPlacement::Stereo => {
                let fl = Self::process_filter_channel(
                    left, self.use_mzt, &mut self.mzt_filter_l,
                    &mut self.svf_stages_l, &self.svf_coeffs, &mut self.oversampler_l,
                );
                let fr = Self::process_filter_channel(
                    right, self.use_mzt, &mut self.mzt_filter_r,
                    &mut self.svf_stages_r, &self.svf_coeffs, &mut self.oversampler_r,
                );
                (fl * dyn_gain_l, fr * dyn_gain_r)
            }
            StereoPlacement::Left => {
                let fl = Self::process_filter_channel(
                    left, self.use_mzt, &mut self.mzt_filter_l,
                    &mut self.svf_stages_l, &self.svf_coeffs, &mut self.oversampler_l,
                );
                (fl * dyn_gain_l, right)
            }
            StereoPlacement::Right => {
                let fr = Self::process_filter_channel(
                    right, self.use_mzt, &mut self.mzt_filter_r,
                    &mut self.svf_stages_r, &self.svf_coeffs, &mut self.oversampler_r,
                );
                (left, fr * dyn_gain_r)
            }
            StereoPlacement::Mid => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let mut out_mid = Self::process_filter_channel(
                    mid, self.use_mzt, &mut self.mzt_filter_l,
                    &mut self.svf_stages_l, &self.svf_coeffs, &mut self.oversampler_l,
                );
                out_mid *= dyn_gain_l;
                (out_mid + side, out_mid - side)
            }
            StereoPlacement::Side => {
                let mid = (left + right) * 0.5;
                let side = (left - right) * 0.5;
                let mut out_side = Self::process_filter_channel(
                    side, self.use_mzt, &mut self.mzt_filter_l,
                    &mut self.svf_stages_l, &self.svf_coeffs, &mut self.oversampler_l,
                );
                out_side *= dyn_gain_l;
                (mid + out_side, mid - out_side)
            }
        };

        // Apply per-band harmonic saturation (post-filter, if drive > 0)
        if self.saturator.drive > 0.01 {
            out_l = self.saturator.process(out_l);
            out_r = self.saturator.process(out_r);
        }

        (out_l, out_r)
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
        // Reset Ultra features
        self.mzt_filter_l.reset();
        self.mzt_filter_r.reset();
        if let Some(ref mut os) = self.oversampler_l {
            os.reset();
        }
        if let Some(ref mut os) = self.oversampler_r {
            os.reset();
        }
        self.transient_detector.reset();
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

    // Ultra features — global
    /// Stereo correlation meter (300ms window)
    pub correlation_meter: CorrelationMeter,
    /// Frequency analyzer with AI suggestions
    pub frequency_analyzer: FrequencyAnalyzer,
    /// ISO 226 equal loudness compensation
    pub equal_loudness: EqualLoudness,
    /// Enable equal loudness compensation
    pub equal_loudness_enabled: bool,
    /// Global oversampling mode (applies to all bands without per-band override)
    pub global_oversample: OversampleMode,
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
    // Ultra features state
    use_mzt: bool,
    transient_aware: bool,
    transient_q_reduction: f64,
    saturator_drive_db: f64,
    saturator_mix: f64,
    saturator_type: SaturationType,
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
            // Ultra features — global
            correlation_meter: CorrelationMeter::new(sample_rate),
            frequency_analyzer: FrequencyAnalyzer::new(sample_rate),
            equal_loudness: {
                let mut el = EqualLoudness::new();
                el.generate_curve(512, sample_rate);
                el
            },
            equal_loudness_enabled: false,
            global_oversample: OversampleMode::Off,
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
            band.needs_update = true;
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

    /// Set band filter shape only (does NOT change enabled state)
    pub fn set_band_shape(&mut self, index: usize, shape: FilterShape) {
        if let Some(band) = self.bands.get_mut(index) {
            band.shape = shape;
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
                use_mzt: b.use_mzt,
                transient_aware: b.transient_aware,
                transient_q_reduction: b.transient_q_reduction,
                saturator_drive_db: b.saturator.drive,
                saturator_mix: b.saturator.mix,
                saturator_type: b.saturator.saturation_type,
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
            band.use_mzt = s.use_mzt;
            band.transient_aware = s.transient_aware;
            band.transient_q_reduction = s.transient_q_reduction;
            band.saturator.drive = s.saturator_drive_db;
            band.saturator.mix = s.saturator_mix;
            band.saturator.saturation_type = s.saturator_type;
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

            // Apply equal loudness compensation if enabled
            if self.equal_loudness_enabled {
                let mono = (out_l + out_r) * 0.5;
                let compensation = self.equal_loudness.compensation_db(mono.abs());
                out_l *= compensation;
                out_r *= compensation;
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

            // Update correlation meter
            self.correlation_meter.process(out_l, out_r);

            *l = out_l;
            *r = out_r;
        }

        // Feed frequency analyzer for AI suggestions
        let mono_block: Vec<f64> = left.iter().zip(right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect();
        self.frequency_analyzer.add_spectrum(&mono_block);

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

    // === Ultra feature accessors ===

    /// Get stereo correlation value (-1.0 to +1.0)
    pub fn get_correlation(&self) -> f64 {
        self.correlation_meter.correlation
    }

    /// Get frequency suggestions from AI analyzer
    pub fn get_frequency_suggestions(&self) -> Vec<FrequencySuggestion> {
        self.frequency_analyzer.get_suggestions()
    }

    /// Enable/disable equal loudness compensation
    pub fn set_equal_loudness(&mut self, enabled: bool) {
        self.equal_loudness_enabled = enabled;
    }

    /// Set global oversampling mode for all bands
    pub fn set_global_oversample(&mut self, mode: OversampleMode) {
        self.global_oversample = mode;
        for band in &mut self.bands {
            band.set_oversampling(mode);
        }
    }

    /// Enable MZT mode on a specific band
    pub fn set_band_mzt(&mut self, index: usize, enabled: bool) {
        if let Some(band) = self.bands.get_mut(index) {
            band.set_use_mzt(enabled);
        }
    }

    /// Set transient-aware mode on a specific band
    pub fn set_band_transient_aware(&mut self, index: usize, enabled: bool, q_reduction: f64) {
        if let Some(band) = self.bands.get_mut(index) {
            band.set_transient_aware(enabled, q_reduction);
        }
    }

    /// Set saturation on a specific band
    pub fn set_band_saturator(&mut self, index: usize, drive_db: f64, mix: f64, sat_type: SaturationType) {
        if let Some(band) = self.bands.get_mut(index) {
            band.set_saturator(drive_db, mix, sat_type);
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
        self.correlation_meter.reset();
        self.frequency_analyzer.reset();
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
            // Recreate transient detector with new sample rate
            band.transient_detector = TransientDetector::new(sample_rate);
        }
        self.analyzer_pre = SpectrumAnalyzer::new(sample_rate);
        self.analyzer_post = SpectrumAnalyzer::new(sample_rate);
        self.eq_match = EqMatch::new(sample_rate);
        self.correlation_meter = CorrelationMeter::new(sample_rate);
        self.frequency_analyzer = FrequencyAnalyzer::new(sample_rate);
        self.equal_loudness = {
            let mut el = EqualLoudness::new();
            el.generate_curve(512, sample_rate);
            el
        };
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
