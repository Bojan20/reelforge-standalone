//! Biquad filter implementation using Transposed Direct Form II
//!
//! TDF-II is numerically optimal for floating-point arithmetic,
//! minimizing quantization noise and ensuring stability.

use rf_core::Sample;
use std::f64::consts::PI;
use std::simd::{f64x4, Simd};

use crate::{MonoProcessor, Processor, ProcessorConfig};

/// Biquad filter types
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FilterType {
    Lowpass,
    Highpass,
    Bandpass,
    Notch,
    Allpass,
    Peaking,
    LowShelf,
    HighShelf,
    Tilt,
}

/// Biquad coefficients
#[derive(Debug, Clone, Copy, Default)]
pub struct BiquadCoeffs {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl BiquadCoeffs {
    /// Calculate lowpass filter coefficients
    pub fn lowpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = (1.0 - cos_omega) / 2.0;
        let b1 = 1.0 - cos_omega;
        let b2 = (1.0 - cos_omega) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate highpass filter coefficients
    pub fn highpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = (1.0 + cos_omega) / 2.0;
        let b1 = -(1.0 + cos_omega);
        let b2 = (1.0 + cos_omega) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate bandpass filter coefficients (constant 0 dB peak gain)
    pub fn bandpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = alpha;
        let b1 = 0.0;
        let b2 = -alpha;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate notch filter coefficients
    pub fn notch(freq: f64, q: f64, sample_rate: f64) -> Self {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = 1.0;
        let b1 = -2.0 * cos_omega;
        let b2 = 1.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate allpass filter coefficients
    pub fn allpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = 1.0 - alpha;
        let b1 = -2.0 * cos_omega;
        let b2 = 1.0 + alpha;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate peaking EQ filter coefficients
    /// gain_db: gain in decibels
    pub fn peaking(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);

        let b0 = 1.0 + alpha * a;
        let b1 = -2.0 * cos_omega;
        let b2 = 1.0 - alpha * a;
        let a0 = 1.0 + alpha / a;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha / a;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate low shelf filter coefficients
    pub fn low_shelf(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let b0 = a * ((a + 1.0) - (a - 1.0) * cos_omega + two_sqrt_a_alpha);
        let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_omega);
        let b2 = a * ((a + 1.0) - (a - 1.0) * cos_omega - two_sqrt_a_alpha);
        let a0 = (a + 1.0) + (a - 1.0) * cos_omega + two_sqrt_a_alpha;
        let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_omega);
        let a2 = (a + 1.0) + (a - 1.0) * cos_omega - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Calculate high shelf filter coefficients
    pub fn high_shelf(freq: f64, q: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let b0 = a * ((a + 1.0) + (a - 1.0) * cos_omega + two_sqrt_a_alpha);
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_omega);
        let b2 = a * ((a + 1.0) + (a - 1.0) * cos_omega - two_sqrt_a_alpha);
        let a0 = (a + 1.0) - (a - 1.0) * cos_omega + two_sqrt_a_alpha;
        let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_omega);
        let a2 = (a + 1.0) - (a - 1.0) * cos_omega - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    /// Bypass (unity gain, no filtering)
    pub fn bypass() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }
}

/// Transposed Direct Form II biquad filter
#[derive(Debug, Clone)]
pub struct BiquadTDF2 {
    coeffs: BiquadCoeffs,
    z1: f64,
    z2: f64,
    sample_rate: f64,
}

impl BiquadTDF2 {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            coeffs: BiquadCoeffs::bypass(),
            z1: 0.0,
            z2: 0.0,
            sample_rate,
        }
    }

    pub fn with_coeffs(coeffs: BiquadCoeffs, sample_rate: f64) -> Self {
        Self {
            coeffs,
            z1: 0.0,
            z2: 0.0,
            sample_rate,
        }
    }

    #[inline]
    pub fn set_coeffs(&mut self, coeffs: BiquadCoeffs) {
        self.coeffs = coeffs;
    }

    #[inline]
    pub fn coeffs(&self) -> &BiquadCoeffs {
        &self.coeffs
    }

    /// Set as lowpass filter
    pub fn set_lowpass(&mut self, freq: f64, q: f64) {
        self.coeffs = BiquadCoeffs::lowpass(freq, q, self.sample_rate);
    }

    /// Set as highpass filter
    pub fn set_highpass(&mut self, freq: f64, q: f64) {
        self.coeffs = BiquadCoeffs::highpass(freq, q, self.sample_rate);
    }

    /// Set as bandpass filter
    pub fn set_bandpass(&mut self, freq: f64, q: f64) {
        self.coeffs = BiquadCoeffs::bandpass(freq, q, self.sample_rate);
    }

    /// Set as notch filter
    pub fn set_notch(&mut self, freq: f64, q: f64) {
        self.coeffs = BiquadCoeffs::notch(freq, q, self.sample_rate);
    }

    /// Set as allpass filter
    pub fn set_allpass(&mut self, freq: f64, q: f64) {
        self.coeffs = BiquadCoeffs::allpass(freq, q, self.sample_rate);
    }

    /// Set as peaking EQ filter
    pub fn set_peaking(&mut self, freq: f64, q: f64, gain_db: f64) {
        self.coeffs = BiquadCoeffs::peaking(freq, q, gain_db, self.sample_rate);
    }

    /// Set as low shelf filter
    pub fn set_low_shelf(&mut self, freq: f64, q: f64, gain_db: f64) {
        self.coeffs = BiquadCoeffs::low_shelf(freq, q, gain_db, self.sample_rate);
    }

    /// Set as high shelf filter
    pub fn set_high_shelf(&mut self, freq: f64, q: f64, gain_db: f64) {
        self.coeffs = BiquadCoeffs::high_shelf(freq, q, gain_db, self.sample_rate);
    }

    /// Set as bypass
    pub fn set_bypass(&mut self) {
        self.coeffs = BiquadCoeffs::bypass();
    }
}

impl Processor for BiquadTDF2 {
    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

impl MonoProcessor for BiquadTDF2 {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let output = self.coeffs.b0 * input + self.z1;
        self.z1 = self.coeffs.b1 * input - self.coeffs.a1 * output + self.z2;
        self.z2 = self.coeffs.b2 * input - self.coeffs.a2 * output;
        output
    }
}

impl ProcessorConfig for BiquadTDF2 {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

/// SIMD-optimized biquad for processing 4 samples in parallel
#[derive(Debug, Clone)]
pub struct BiquadSimd4 {
    // Coefficients as SIMD vectors
    b0: f64x4,
    b1: f64x4,
    b2: f64x4,
    a1: f64x4,
    a2: f64x4,
    // State for 4 parallel filters
    z1: f64x4,
    z2: f64x4,
    sample_rate: f64,
}

impl BiquadSimd4 {
    pub fn new(sample_rate: f64) -> Self {
        let coeffs = BiquadCoeffs::bypass();
        Self {
            b0: f64x4::splat(coeffs.b0),
            b1: f64x4::splat(coeffs.b1),
            b2: f64x4::splat(coeffs.b2),
            a1: f64x4::splat(coeffs.a1),
            a2: f64x4::splat(coeffs.a2),
            z1: f64x4::splat(0.0),
            z2: f64x4::splat(0.0),
            sample_rate,
        }
    }

    pub fn set_coeffs(&mut self, coeffs: BiquadCoeffs) {
        self.b0 = f64x4::splat(coeffs.b0);
        self.b1 = f64x4::splat(coeffs.b1);
        self.b2 = f64x4::splat(coeffs.b2);
        self.a1 = f64x4::splat(coeffs.a1);
        self.a2 = f64x4::splat(coeffs.a2);
    }

    /// Process 4 samples at once (for 4 parallel channels or interleaved processing)
    #[inline(always)]
    pub fn process_simd(&mut self, input: f64x4) -> f64x4 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }

    /// Process a mono block using SIMD (4 samples at a time)
    pub fn process_block(&mut self, buffer: &mut [Sample]) {
        let len = buffer.len();
        let simd_len = len - (len % 4);

        // Process 4 samples at a time
        for i in (0..simd_len).step_by(4) {
            let input = f64x4::from_slice(&buffer[i..]);
            let output = self.process_simd(input);
            buffer[i..i + 4].copy_from_slice(&output.to_array());
        }

        // Handle remaining samples with scalar processing
        // For remaining samples, we need a scalar biquad
        // This is a simplified handling - in production, maintain separate scalar state
        for i in simd_len..len {
            let input = f64x4::splat(buffer[i]);
            let output = self.process_simd(input);
            buffer[i] = output[0];
        }
    }

    pub fn reset(&mut self) {
        self.z1 = f64x4::splat(0.0);
        self.z2 = f64x4::splat(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bypass() {
        let mut filter = BiquadTDF2::new(48000.0);
        filter.set_bypass();

        let input = 0.5;
        let output = filter.process_sample(input);
        assert!((output - input).abs() < 1e-10);
    }

    #[test]
    fn test_lowpass_dc() {
        let mut filter = BiquadTDF2::new(48000.0);
        filter.set_lowpass(1000.0, 0.707);

        // DC signal should pass through lowpass
        for _ in 0..1000 {
            filter.process_sample(1.0);
        }
        let output = filter.process_sample(1.0);
        assert!((output - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_highpass_dc() {
        let mut filter = BiquadTDF2::new(48000.0);
        filter.set_highpass(1000.0, 0.707);

        // DC signal should be blocked by highpass
        for _ in 0..1000 {
            filter.process_sample(1.0);
        }
        let output = filter.process_sample(1.0);
        assert!(output.abs() < 0.01);
    }

    #[test]
    fn test_reset() {
        let mut filter = BiquadTDF2::new(48000.0);
        filter.set_lowpass(1000.0, 0.707);

        // Process some samples
        for _ in 0..100 {
            filter.process_sample(1.0);
        }

        // Reset
        filter.reset();

        // State should be cleared
        assert_eq!(filter.z1, 0.0);
        assert_eq!(filter.z2, 0.0);
    }
}
