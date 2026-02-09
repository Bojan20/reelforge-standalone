//! Global Oversampling System
//!
//! Universal oversampling for all DSP processors:
//! - 2x, 4x, 8x, 16x modes
//! - Linear phase FIR upsampling/downsampling
//! - Anti-aliasing built in
//! - SIMD-optimized polyphase filters
//!
//! Eliminates aliasing artifacts from:
//! - Saturation/Distortion
//! - Waveshaping
//! - Dynamics (compressor/limiter)
//! - Non-linear EQ

use rf_core::Sample;
use std::f64::consts::PI;

#[cfg(target_arch = "x86_64")]
use std::simd::{f64x4, f64x8, num::SimdFloat};

// ═══════════════════════════════════════════════════════════════════════════════
// OVERSAMPLING MODES
// ═══════════════════════════════════════════════════════════════════════════════

/// Oversampling factor
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OversampleFactor {
    /// No oversampling (1x)
    #[default]
    X1,
    /// 2x oversampling
    X2,
    /// 4x oversampling
    X4,
    /// 8x oversampling
    X8,
    /// 16x oversampling (maximum quality)
    X16,
}

impl OversampleFactor {
    pub fn factor(&self) -> usize {
        match self {
            Self::X1 => 1,
            Self::X2 => 2,
            Self::X4 => 4,
            Self::X8 => 8,
            Self::X16 => 16,
        }
    }

    /// Get filter order for this factor
    fn filter_order(&self) -> usize {
        match self {
            Self::X1 => 0,
            Self::X2 => 32,
            Self::X4 => 64,
            Self::X8 => 96,
            Self::X16 => 128,
        }
    }
}

/// Oversampling quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OversampleQuality {
    /// Fast (steeper transition, more aliasing)
    Fast,
    /// Standard quality
    #[default]
    Standard,
    /// High quality (gentle transition)
    High,
    /// Maximum quality (for mastering)
    Maximum,
}

impl OversampleQuality {
    /// Get transition band width (0-1, fraction of Nyquist)
    fn transition_width(&self) -> f64 {
        match self {
            Self::Fast => 0.2,
            Self::Standard => 0.1,
            Self::High => 0.05,
            Self::Maximum => 0.02,
        }
    }

    /// Get stopband attenuation in dB
    fn stopband_atten(&self) -> f64 {
        match self {
            Self::Fast => 60.0,
            Self::Standard => 96.0,
            Self::High => 120.0,
            Self::Maximum => 144.0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// POLYPHASE FIR FILTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Polyphase FIR filter for efficient oversampling
#[derive(Debug, Clone)]
pub struct PolyphaseFilter {
    /// Number of phases (= oversampling factor)
    num_phases: usize,
    /// Taps per phase
    taps_per_phase: usize,
    /// Coefficients organized by phase [phase][tap]
    coeffs: Vec<Vec<f64>>,
    /// Filter state (delay line)
    state: Vec<f64>,
    /// Current position in state buffer
    state_pos: usize,
}

impl PolyphaseFilter {
    /// Create polyphase filter for given oversampling factor
    pub fn new(factor: OversampleFactor, quality: OversampleQuality) -> Self {
        let num_phases = factor.factor();
        if num_phases == 1 {
            return Self {
                num_phases: 1,
                taps_per_phase: 1,
                coeffs: vec![vec![1.0]],
                state: vec![0.0],
                state_pos: 0,
            };
        }

        let total_taps = factor.filter_order();
        let taps_per_phase = total_taps / num_phases;

        // Generate lowpass FIR
        let cutoff = 0.5 / num_phases as f64;
        let transition = quality.transition_width() / num_phases as f64;
        let atten = quality.stopband_atten();

        let prototype = Self::design_lowpass(total_taps, cutoff, transition, atten);

        // Decompose into polyphase
        let mut coeffs = vec![vec![0.0; taps_per_phase]; num_phases];
        for (i, &c) in prototype.iter().enumerate() {
            let phase = i % num_phases;
            let tap = i / num_phases;
            if tap < taps_per_phase {
                coeffs[phase][tap] = c * num_phases as f64; // Compensate for interpolation gain
            }
        }

        Self {
            num_phases,
            taps_per_phase,
            coeffs,
            state: vec![0.0; taps_per_phase],
            state_pos: 0,
        }
    }

    /// Design lowpass FIR using Kaiser window
    fn design_lowpass(num_taps: usize, cutoff: f64, transition: f64, atten_db: f64) -> Vec<f64> {
        let mut coeffs = vec![0.0; num_taps];
        let m = num_taps - 1;

        // Calculate Kaiser beta from desired attenuation
        let beta = if atten_db > 50.0 {
            0.1102 * (atten_db - 8.7)
        } else if atten_db >= 21.0 {
            0.5842 * (atten_db - 21.0).powf(0.4) + 0.07886 * (atten_db - 21.0)
        } else {
            0.0
        };

        // Generate windowed sinc
        let fc = cutoff + transition / 2.0;
        for i in 0..num_taps {
            let n = i as f64 - m as f64 / 2.0;

            // Sinc function
            let sinc = if n.abs() < 1e-10 {
                2.0 * fc
            } else {
                (2.0 * PI * fc * n).sin() / (PI * n)
            };

            // Kaiser window
            let alpha = m as f64 / 2.0;
            let arg = 1.0 - ((i as f64 - alpha) / alpha).powi(2);
            let window = if arg > 0.0 {
                bessel_i0(beta * arg.sqrt()) / bessel_i0(beta)
            } else {
                0.0
            };

            coeffs[i] = sinc * window;
        }

        // Normalize for unity gain at DC
        let sum: f64 = coeffs.iter().sum();
        if sum.abs() > 1e-10 {
            for c in &mut coeffs {
                *c /= sum;
            }
        }

        coeffs
    }

    /// Upsample single sample, returns num_phases samples
    pub fn upsample(&mut self, input: Sample) -> Vec<Sample> {
        // Add input to state buffer
        self.state[self.state_pos] = input;

        let mut output = vec![0.0; self.num_phases];

        for phase in 0..self.num_phases {
            let mut sum = 0.0;
            for tap in 0..self.taps_per_phase {
                let state_idx = (self.state_pos + self.taps_per_phase - tap) % self.taps_per_phase;
                sum += self.state[state_idx] * self.coeffs[phase][tap];
            }
            output[phase] = sum;
        }

        self.state_pos = (self.state_pos + 1) % self.taps_per_phase;

        output
    }

    /// Downsample: takes num_phases samples, returns 1 sample
    pub fn downsample(&mut self, input: &[Sample]) -> Sample {
        debug_assert_eq!(input.len(), self.num_phases);

        // Only process phase 0 (decimate)
        self.state[self.state_pos] = input[0];

        let mut sum = 0.0;
        for tap in 0..self.taps_per_phase {
            let state_idx = (self.state_pos + self.taps_per_phase - tap) % self.taps_per_phase;
            sum += self.state[state_idx] * self.coeffs[0][tap];
        }

        self.state_pos = (self.state_pos + 1) % self.taps_per_phase;

        sum
    }

    /// Reset filter state
    pub fn reset(&mut self) {
        self.state.fill(0.0);
        self.state_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OVERSAMPLER
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete oversampler (upsample → process → downsample)
#[derive(Debug, Clone)]
pub struct GlobalOversampler {
    /// Oversampling factor
    factor: OversampleFactor,
    /// Quality setting
    quality: OversampleQuality,
    /// Upsampling filter L
    upsample_l: PolyphaseFilter,
    /// Upsampling filter R
    upsample_r: PolyphaseFilter,
    /// Downsampling filter L
    downsample_l: PolyphaseFilter,
    /// Downsampling filter R
    downsample_r: PolyphaseFilter,
    /// Internal buffer for upsampled data
    os_buffer_l: Vec<f64>,
    os_buffer_r: Vec<f64>,
    /// Enabled state
    enabled: bool,
}

impl GlobalOversampler {
    /// Create oversampler with given settings
    pub fn new(factor: OversampleFactor, quality: OversampleQuality) -> Self {
        Self {
            factor,
            quality,
            upsample_l: PolyphaseFilter::new(factor, quality),
            upsample_r: PolyphaseFilter::new(factor, quality),
            downsample_l: PolyphaseFilter::new(factor, quality),
            downsample_r: PolyphaseFilter::new(factor, quality),
            os_buffer_l: Vec::with_capacity(1024 * factor.factor()),
            os_buffer_r: Vec::with_capacity(1024 * factor.factor()),
            enabled: factor != OversampleFactor::X1,
        }
    }

    /// Create 4x oversampler (good default)
    pub fn x4() -> Self {
        Self::new(OversampleFactor::X4, OversampleQuality::Standard)
    }

    /// Create 8x oversampler (high quality)
    pub fn x8_hq() -> Self {
        Self::new(OversampleFactor::X8, OversampleQuality::High)
    }

    /// Get current factor
    pub fn factor(&self) -> usize {
        self.factor.factor()
    }

    /// Set oversampling factor
    pub fn set_factor(&mut self, factor: OversampleFactor) {
        if factor != self.factor {
            self.factor = factor;
            self.upsample_l = PolyphaseFilter::new(factor, self.quality);
            self.upsample_r = PolyphaseFilter::new(factor, self.quality);
            self.downsample_l = PolyphaseFilter::new(factor, self.quality);
            self.downsample_r = PolyphaseFilter::new(factor, self.quality);
            self.enabled = factor != OversampleFactor::X1;
        }
    }

    /// Enable/disable oversampling
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled && self.factor != OversampleFactor::X1;
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        if !self.enabled {
            return 0;
        }
        // Each polyphase filter adds taps_per_phase / 2 samples latency
        // Both upsample and downsample contribute

        self.factor.filter_order() / self.factor.factor()
    }

    /// Process stereo with given processor function
    /// The processor receives oversampled buffers and processes them in-place
    pub fn process<F>(&mut self, left: &mut [Sample], right: &mut [Sample], mut processor: F)
    where
        F: FnMut(&mut [Sample], &mut [Sample]),
    {
        if !self.enabled || self.factor == OversampleFactor::X1 {
            processor(left, right);
            return;
        }

        let len = left.len();
        let os_len = len * self.factor();

        // Resize buffers if needed
        if self.os_buffer_l.len() < os_len {
            self.os_buffer_l.resize(os_len, 0.0);
            self.os_buffer_r.resize(os_len, 0.0);
        }

        // Upsample
        let factor = self.factor();
        for i in 0..len {
            let up_l = self.upsample_l.upsample(left[i]);
            let up_r = self.upsample_r.upsample(right[i]);

            for j in 0..factor {
                self.os_buffer_l[i * factor + j] = up_l[j];
                self.os_buffer_r[i * factor + j] = up_r[j];
            }
        }

        // Process at oversampled rate
        processor(
            &mut self.os_buffer_l[..os_len],
            &mut self.os_buffer_r[..os_len],
        );

        // Downsample
        for i in 0..len {
            let start = i * factor;
            left[i] = self
                .downsample_l
                .downsample(&self.os_buffer_l[start..start + factor]);
            right[i] = self
                .downsample_r
                .downsample(&self.os_buffer_r[start..start + factor]);
        }
    }

    /// Reset all filters
    pub fn reset(&mut self) {
        self.upsample_l.reset();
        self.upsample_r.reset();
        self.downsample_l.reset();
        self.downsample_r.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIMD BATCH BIQUAD PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

/// SIMD-optimized biquad coefficients for batch processing
#[derive(Debug, Clone)]
pub struct SimdBiquadBank {
    /// b0 coefficients (4 filters)
    b0: [f64; 4],
    /// b1 coefficients
    b1: [f64; 4],
    /// b2 coefficients
    b2: [f64; 4],
    /// a1 coefficients (negated for direct form)
    a1: [f64; 4],
    /// a2 coefficients (negated)
    a2: [f64; 4],
    /// State z1 for each filter
    z1: [f64; 4],
    /// State z2 for each filter
    z2: [f64; 4],
}

impl SimdBiquadBank {
    /// Create empty bank (bypassed)
    pub fn new() -> Self {
        Self {
            b0: [1.0; 4],
            b1: [0.0; 4],
            b2: [0.0; 4],
            a1: [0.0; 4],
            a2: [0.0; 4],
            z1: [0.0; 4],
            z2: [0.0; 4],
        }
    }

    /// Set coefficients for one filter in the bank
    pub fn set_filter(&mut self, index: usize, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) {
        if index < 4 {
            self.b0[index] = b0;
            self.b1[index] = b1;
            self.b2[index] = b2;
            self.a1[index] = -a1; // Negate for direct form II
            self.a2[index] = -a2;
        }
    }

    /// Process 4 samples through 4 parallel filters using SIMD
    #[cfg(target_arch = "x86_64")]
    pub fn process_simd(&mut self, input: [f64; 4]) -> [f64; 4] {
        let x = f64x4::from_array(input);
        let b0 = f64x4::from_array(self.b0);
        let b1 = f64x4::from_array(self.b1);
        let b2 = f64x4::from_array(self.b2);
        let a1 = f64x4::from_array(self.a1);
        let a2 = f64x4::from_array(self.a2);
        let z1 = f64x4::from_array(self.z1);
        let z2 = f64x4::from_array(self.z2);

        // TDF-II: y = b0*x + z1
        //         z1 = b1*x + a1*y + z2
        //         z2 = b2*x + a2*y
        let y = b0 * x + z1;
        let new_z1 = b1 * x + a1 * y + z2;
        let new_z2 = b2 * x + a2 * y;

        self.z1 = new_z1.to_array();
        self.z2 = new_z2.to_array();

        y.to_array()
    }

    /// Scalar fallback for non-SIMD platforms
    #[cfg(not(target_arch = "x86_64"))]
    pub fn process_simd(&mut self, input: [f64; 4]) -> [f64; 4] {
        let mut output = [0.0; 4];
        for i in 0..4 {
            let y = self.b0[i] * input[i] + self.z1[i];
            self.z1[i] = self.b1[i] * input[i] + self.a1[i] * y + self.z2[i];
            self.z2[i] = self.b2[i] * input[i] + self.a2[i] * y;
            output[i] = y;
        }
        output
    }

    /// Reset all filter states
    pub fn reset(&mut self) {
        self.z1 = [0.0; 4];
        self.z2 = [0.0; 4];
    }
}

impl Default for SimdBiquadBank {
    fn default() -> Self {
        Self::new()
    }
}

/// Process 8 parallel biquads using AVX
#[derive(Debug, Clone)]
pub struct SimdBiquadBank8 {
    b0: [f64; 8],
    b1: [f64; 8],
    b2: [f64; 8],
    a1: [f64; 8],
    a2: [f64; 8],
    z1: [f64; 8],
    z2: [f64; 8],
}

impl SimdBiquadBank8 {
    pub fn new() -> Self {
        Self {
            b0: [1.0; 8],
            b1: [0.0; 8],
            b2: [0.0; 8],
            a1: [0.0; 8],
            a2: [0.0; 8],
            z1: [0.0; 8],
            z2: [0.0; 8],
        }
    }

    pub fn set_filter(&mut self, index: usize, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) {
        if index < 8 {
            self.b0[index] = b0;
            self.b1[index] = b1;
            self.b2[index] = b2;
            self.a1[index] = -a1;
            self.a2[index] = -a2;
        }
    }

    #[cfg(target_arch = "x86_64")]
    pub fn process_simd(&mut self, input: [f64; 8]) -> [f64; 8] {
        let x = f64x8::from_array(input);
        let b0 = f64x8::from_array(self.b0);
        let b1 = f64x8::from_array(self.b1);
        let b2 = f64x8::from_array(self.b2);
        let a1 = f64x8::from_array(self.a1);
        let a2 = f64x8::from_array(self.a2);
        let z1 = f64x8::from_array(self.z1);
        let z2 = f64x8::from_array(self.z2);

        let y = b0 * x + z1;
        let new_z1 = b1 * x + a1 * y + z2;
        let new_z2 = b2 * x + a2 * y;

        self.z1 = new_z1.to_array();
        self.z2 = new_z2.to_array();

        y.to_array()
    }

    #[cfg(not(target_arch = "x86_64"))]
    pub fn process_simd(&mut self, input: [f64; 8]) -> [f64; 8] {
        let mut output = [0.0; 8];
        for i in 0..8 {
            let y = self.b0[i] * input[i] + self.z1[i];
            self.z1[i] = self.b1[i] * input[i] + self.a1[i] * y + self.z2[i];
            self.z2[i] = self.b2[i] * input[i] + self.a2[i] * y;
            output[i] = y;
        }
        output
    }

    pub fn reset(&mut self) {
        self.z1 = [0.0; 8];
        self.z2 = [0.0; 8];
    }
}

impl Default for SimdBiquadBank8 {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Modified Bessel function I0
fn bessel_i0(x: f64) -> f64 {
    let ax = x.abs();
    if ax < 3.75 {
        let y = (x / 3.75).powi(2);
        1.0 + y
            * (3.5156229
                + y * (3.0899424
                    + y * (1.2067492 + y * (0.2659732 + y * (0.0360768 + y * 0.0045813)))))
    } else {
        let y = 3.75 / ax;
        (ax.exp() / ax.sqrt())
            * (0.39894228
                + y * (0.01328592
                    + y * (0.00225319
                        + y * (-0.00157565
                            + y * (0.00916281
                                + y * (-0.02057706
                                    + y * (0.02635537 + y * (-0.01647633 + y * 0.00392377))))))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oversampler_factor() {
        assert_eq!(OversampleFactor::X1.factor(), 1);
        assert_eq!(OversampleFactor::X4.factor(), 4);
        assert_eq!(OversampleFactor::X8.factor(), 8);
    }

    #[test]
    fn test_simd_biquad_bank() {
        let mut bank = SimdBiquadBank::new();

        // All pass-through
        let output = bank.process_simd([1.0, 2.0, 3.0, 4.0]);
        assert!((output[0] - 1.0).abs() < 1e-10);
        assert!((output[1] - 2.0).abs() < 1e-10);
    }

    #[test]
    fn test_polyphase_identity() {
        let filter = PolyphaseFilter::new(OversampleFactor::X1, OversampleQuality::Standard);
        assert_eq!(filter.num_phases, 1);
    }
}
