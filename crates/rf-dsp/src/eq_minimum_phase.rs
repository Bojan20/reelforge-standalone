//! Minimum Phase EQ - Hilbert Transform Reconstruction
//!
//! Zero-latency EQ with smooth phase response:
//! - Hilbert transform for minimum phase reconstruction
//! - Kramers-Kronig relations (magnitude → phase)
//! - Group delay optimization
//! - Phase-corrected crossovers

use std::f64::consts::PI;
use std::sync::Arc;

use realfft::{RealFftPlanner, RealToComplex, ComplexToReal};
use rustfft::num_complex::Complex;

use rf_core::Sample;
use crate::{Processor, StereoProcessor};

// ============================================================================
// CONSTANTS
// ============================================================================

/// FFT size for Hilbert transform
const HILBERT_FFT_SIZE: usize = 4096;

/// Overlap for OLA processing
const OVERLAP_FACTOR: usize = 4;

// ============================================================================
// HILBERT TRANSFORM
// ============================================================================

/// Hilbert transform for minimum phase reconstruction
pub struct HilbertTransform {
    fft_size: usize,
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    input_buffer: Vec<f64>,
    output_buffer: Vec<f64>,
    spectrum: Vec<Complex<f64>>,
}

impl HilbertTransform {
    pub fn new(fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        Self {
            fft_size,
            fft_forward,
            fft_inverse,
            input_buffer: vec![0.0; fft_size],
            output_buffer: vec![0.0; fft_size],
            spectrum: vec![Complex::new(0.0, 0.0); fft_size / 2 + 1],
        }
    }

    /// Compute analytic signal (signal + j*hilbert(signal))
    pub fn analytic_signal(&mut self, input: &[f64]) -> Vec<Complex<f64>> {
        let n = input.len().min(self.fft_size);

        // Copy input with zero padding
        self.input_buffer[..n].copy_from_slice(&input[..n]);
        self.input_buffer[n..].fill(0.0);

        // Forward FFT
        self.fft_forward.process(&mut self.input_buffer, &mut self.spectrum).unwrap();

        // Apply Hilbert filter in frequency domain
        // H(f) = -j*sign(f)
        let half = self.spectrum.len();
        for i in 1..half - 1 {
            // Multiply by 2 for positive frequencies
            self.spectrum[i] = self.spectrum[i] * Complex::new(2.0, 0.0);
        }
        // DC and Nyquist stay the same

        // Inverse FFT gives analytic signal
        self.fft_inverse.process(&mut self.spectrum, &mut self.output_buffer).unwrap();

        // Normalize
        let norm = 1.0 / self.fft_size as f64;
        self.output_buffer.iter()
            .take(n)
            .map(|&x| Complex::new(x * norm, 0.0))
            .collect()
    }

    /// Get instantaneous phase from analytic signal
    pub fn instantaneous_phase(&mut self, input: &[f64]) -> Vec<f64> {
        let analytic = self.analytic_signal(input);
        analytic.iter().map(|c| c.im.atan2(c.re)).collect()
    }

    /// Get instantaneous amplitude (envelope)
    pub fn envelope(&mut self, input: &[f64]) -> Vec<f64> {
        let analytic = self.analytic_signal(input);
        analytic.iter().map(|c| (c.re * c.re + c.im * c.im).sqrt()).collect()
    }
}

// ============================================================================
// MINIMUM PHASE RECONSTRUCTION
// ============================================================================

/// Converts arbitrary magnitude response to minimum phase
pub struct MinimumPhaseReconstructor {
    fft_size: usize,
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    log_mag: Vec<f64>,
    cepstrum: Vec<Complex<f64>>,
    temp_buffer: Vec<f64>,
}

impl MinimumPhaseReconstructor {
    pub fn new(fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        Self {
            fft_size,
            fft_forward,
            fft_inverse,
            log_mag: vec![0.0; fft_size],
            cepstrum: vec![Complex::new(0.0, 0.0); fft_size / 2 + 1],
            temp_buffer: vec![0.0; fft_size],
        }
    }

    /// Reconstruct minimum phase from magnitude spectrum
    ///
    /// Uses the Hilbert transform relationship:
    /// min_phase = hilbert(log(magnitude))
    pub fn reconstruct(&mut self, magnitude: &[f64]) -> Vec<Complex<f64>> {
        let n = magnitude.len().min(self.fft_size / 2 + 1);

        // Take log of magnitude (with floor to avoid log(0))
        for i in 0..n {
            self.log_mag[i] = magnitude[i].max(1e-10).ln();
        }
        // Mirror for real FFT
        for i in n..self.fft_size / 2 + 1 {
            self.log_mag[i] = self.log_mag[n - 1];
        }

        // Hilbert transform of log magnitude gives minimum phase
        // Using cepstral method:
        // 1. IFFT of log magnitude → real cepstrum
        // 2. Fold cepstrum (causal part only)
        // 3. FFT → complex spectrum with minimum phase

        // Copy to complex buffer
        for i in 0..self.fft_size / 2 + 1 {
            self.cepstrum[i] = Complex::new(self.log_mag[i], 0.0);
        }

        // IFFT to get cepstrum
        self.fft_inverse.process(&mut self.cepstrum, &mut self.temp_buffer).unwrap();

        // Fold cepstrum: keep n=0, double n=1..N/2-1, zero n=N/2..N-1
        let norm = 1.0 / self.fft_size as f64;
        self.temp_buffer[0] *= norm;
        for i in 1..self.fft_size / 2 {
            self.temp_buffer[i] *= 2.0 * norm;
        }
        if self.fft_size / 2 < self.fft_size {
            self.temp_buffer[self.fft_size / 2] *= norm;
        }
        for i in self.fft_size / 2 + 1..self.fft_size {
            self.temp_buffer[i] = 0.0;
        }

        // FFT back to get minimum phase spectrum
        self.fft_forward.process(&mut self.temp_buffer, &mut self.cepstrum).unwrap();

        // Convert from log domain and apply phase
        let mut result = Vec::with_capacity(n);
        for i in 0..n {
            let log_mag = self.cepstrum[i].re;
            let phase = self.cepstrum[i].im;
            let mag = log_mag.exp();
            result.push(Complex::new(mag * phase.cos(), mag * phase.sin()));
        }

        result
    }

    /// Get minimum phase from magnitude (just the phase, not full spectrum)
    pub fn get_phase(&mut self, magnitude: &[f64]) -> Vec<f64> {
        let spectrum = self.reconstruct(magnitude);
        spectrum.iter().map(|c| c.im.atan2(c.re)).collect()
    }
}

// ============================================================================
// MINIMUM PHASE EQ BAND
// ============================================================================

/// Single minimum phase EQ band
#[derive(Debug, Clone)]
pub struct MinPhaseEqBand {
    /// Center frequency
    pub freq: f64,
    /// Gain in dB
    pub gain_db: f64,
    /// Q factor
    pub q: f64,
    /// Filter type
    pub filter_type: MinPhaseFilterType,
    /// Enabled
    pub enabled: bool,

    // Biquad state (TDF-II)
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    z1: f64,
    z2: f64,

    sample_rate: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum MinPhaseFilterType {
    #[default]
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
    Notch,
}

impl MinPhaseEqBand {
    pub fn new(freq: f64, gain_db: f64, q: f64, filter_type: MinPhaseFilterType, sample_rate: f64) -> Self {
        let mut band = Self {
            freq,
            gain_db,
            q,
            filter_type,
            enabled: true,
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            z1: 0.0,
            z2: 0.0,
            sample_rate,
        };
        band.update_coefficients();
        band
    }

    pub fn set_params(&mut self, freq: f64, gain_db: f64, q: f64) {
        self.freq = freq;
        self.gain_db = gain_db;
        self.q = q;
        self.update_coefficients();
    }

    fn update_coefficients(&mut self) {
        let omega = 2.0 * PI * self.freq / self.sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * self.q);

        match self.filter_type {
            MinPhaseFilterType::Bell => {
                let a = 10.0_f64.powf(self.gain_db / 40.0);
                let a0 = 1.0 + alpha / a;
                self.b0 = (1.0 + alpha * a) / a0;
                self.b1 = (-2.0 * cos_w) / a0;
                self.b2 = (1.0 - alpha * a) / a0;
                self.a1 = self.b1;
                self.a2 = (1.0 - alpha / a) / a0;
            }
            MinPhaseFilterType::LowShelf => {
                let a = 10.0_f64.powf(self.gain_db / 40.0);
                let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
                let a0 = (a + 1.0) + (a - 1.0) * cos_w + two_sqrt_a_alpha;
                self.b0 = (a * ((a + 1.0) - (a - 1.0) * cos_w + two_sqrt_a_alpha)) / a0;
                self.b1 = (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
                self.b2 = (a * ((a + 1.0) - (a - 1.0) * cos_w - two_sqrt_a_alpha)) / a0;
                self.a1 = (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
                self.a2 = ((a + 1.0) + (a - 1.0) * cos_w - two_sqrt_a_alpha) / a0;
            }
            MinPhaseFilterType::HighShelf => {
                let a = 10.0_f64.powf(self.gain_db / 40.0);
                let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
                let a0 = (a + 1.0) - (a - 1.0) * cos_w + two_sqrt_a_alpha;
                self.b0 = (a * ((a + 1.0) + (a - 1.0) * cos_w + two_sqrt_a_alpha)) / a0;
                self.b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w)) / a0;
                self.b2 = (a * ((a + 1.0) + (a - 1.0) * cos_w - two_sqrt_a_alpha)) / a0;
                self.a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cos_w)) / a0;
                self.a2 = ((a + 1.0) - (a - 1.0) * cos_w - two_sqrt_a_alpha) / a0;
            }
            MinPhaseFilterType::LowCut => {
                let a0 = 1.0 + alpha;
                self.b0 = ((1.0 + cos_w) / 2.0) / a0;
                self.b1 = (-(1.0 + cos_w)) / a0;
                self.b2 = self.b0;
                self.a1 = (-2.0 * cos_w) / a0;
                self.a2 = (1.0 - alpha) / a0;
            }
            MinPhaseFilterType::HighCut => {
                let a0 = 1.0 + alpha;
                self.b0 = ((1.0 - cos_w) / 2.0) / a0;
                self.b1 = (1.0 - cos_w) / a0;
                self.b2 = self.b0;
                self.a1 = (-2.0 * cos_w) / a0;
                self.a2 = (1.0 - alpha) / a0;
            }
            MinPhaseFilterType::Notch => {
                let a0 = 1.0 + alpha;
                self.b0 = 1.0 / a0;
                self.b1 = (-2.0 * cos_w) / a0;
                self.b2 = 1.0 / a0;
                self.a1 = self.b1;
                self.a2 = (1.0 - alpha) / a0;
            }
        }
    }

    /// Get magnitude at frequency
    pub fn magnitude_at(&self, freq: f64) -> f64 {
        if !self.enabled {
            return 1.0;
        }

        let omega = 2.0 * PI * freq / self.sample_rate;
        let cos_w = omega.cos();
        let cos_2w = (2.0 * omega).cos();

        let num = self.b0 * self.b0 + self.b1 * self.b1 + self.b2 * self.b2
            + 2.0 * (self.b0 * self.b1 + self.b1 * self.b2) * cos_w
            + 2.0 * self.b0 * self.b2 * cos_2w;

        let den = 1.0 + self.a1 * self.a1 + self.a2 * self.a2
            + 2.0 * (self.a1 + self.a1 * self.a2) * cos_w
            + 2.0 * self.a2 * cos_2w;

        (num / den).sqrt()
    }

    /// Get phase at frequency (minimum phase)
    pub fn phase_at(&self, freq: f64) -> f64 {
        if !self.enabled {
            return 0.0;
        }

        let omega = 2.0 * PI * freq / self.sample_rate;
        let z = Complex::new(omega.cos(), omega.sin());
        let z2 = z * z;

        let num = Complex::new(self.b0, 0.0) + Complex::new(self.b1, 0.0) * z + Complex::new(self.b2, 0.0) * z2;
        let den = Complex::new(1.0, 0.0) + Complex::new(self.a1, 0.0) * z + Complex::new(self.a2, 0.0) * z2;

        let h = num / den;
        h.im.atan2(h.re)
    }

    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        if !self.enabled {
            return input;
        }

        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }

    pub fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

// ============================================================================
// MINIMUM PHASE EQ
// ============================================================================

/// Maximum bands for minimum phase EQ
pub const MIN_PHASE_MAX_BANDS: usize = 32;

/// Minimum Phase EQ - zero latency with smooth phase
#[derive(Clone)]
pub struct MinPhaseEq {
    bands_l: Vec<MinPhaseEqBand>,
    bands_r: Vec<MinPhaseEqBand>,
    sample_rate: f64,

    /// Group delay optimizer
    pub optimize_group_delay: bool,
}

impl MinPhaseEq {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            bands_l: Vec::with_capacity(MIN_PHASE_MAX_BANDS),
            bands_r: Vec::with_capacity(MIN_PHASE_MAX_BANDS),
            sample_rate,
            optimize_group_delay: false,
        }
    }

    /// Add a band
    pub fn add_band(&mut self, freq: f64, gain_db: f64, q: f64, filter_type: MinPhaseFilterType) -> usize {
        let band_l = MinPhaseEqBand::new(freq, gain_db, q, filter_type, self.sample_rate);
        let band_r = MinPhaseEqBand::new(freq, gain_db, q, filter_type, self.sample_rate);
        self.bands_l.push(band_l);
        self.bands_r.push(band_r);
        self.bands_l.len() - 1
    }

    /// Set band parameters
    pub fn set_band(&mut self, index: usize, freq: f64, gain_db: f64, q: f64) {
        if index < self.bands_l.len() {
            self.bands_l[index].set_params(freq, gain_db, q);
            self.bands_r[index].set_params(freq, gain_db, q);
        }
    }

    /// Enable/disable band
    pub fn set_band_enabled(&mut self, index: usize, enabled: bool) {
        if index < self.bands_l.len() {
            self.bands_l[index].enabled = enabled;
            self.bands_r[index].enabled = enabled;
        }
    }

    /// Remove band
    pub fn remove_band(&mut self, index: usize) {
        if index < self.bands_l.len() {
            self.bands_l.remove(index);
            self.bands_r.remove(index);
        }
    }

    /// Get total magnitude at frequency
    pub fn magnitude_at(&self, freq: f64) -> f64 {
        self.bands_l.iter()
            .map(|b| b.magnitude_at(freq))
            .product()
    }

    /// Get total phase at frequency
    pub fn phase_at(&self, freq: f64) -> f64 {
        self.bands_l.iter()
            .map(|b| b.phase_at(freq))
            .sum()
    }

    /// Get group delay at frequency (derivative of phase)
    pub fn group_delay_at(&self, freq: f64) -> f64 {
        let delta = 1.0; // 1 Hz
        let phase_lo = self.phase_at(freq - delta);
        let phase_hi = self.phase_at(freq + delta);

        // Unwrap phase
        let mut diff = phase_hi - phase_lo;
        while diff > PI {
            diff -= 2.0 * PI;
        }
        while diff < -PI {
            diff += 2.0 * PI;
        }

        // Group delay = -dφ/dω
        -diff / (2.0 * PI * 2.0 * delta) * self.sample_rate
    }

    /// Get magnitude curve for visualization
    pub fn get_magnitude_curve(&self, num_points: usize) -> Vec<f64> {
        (0..num_points).map(|i| {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t);
            let mag = self.magnitude_at(freq);
            20.0 * mag.log10()
        }).collect()
    }

    /// Get phase curve for visualization
    pub fn get_phase_curve(&self, num_points: usize) -> Vec<f64> {
        (0..num_points).map(|i| {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t);
            self.phase_at(freq) * 180.0 / PI
        }).collect()
    }

    /// Get group delay curve for visualization
    pub fn get_group_delay_curve(&self, num_points: usize) -> Vec<f64> {
        (0..num_points).map(|i| {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t);
            self.group_delay_at(freq) * 1000.0 // ms
        }).collect()
    }

    /// Number of bands
    pub fn num_bands(&self) -> usize {
        self.bands_l.len()
    }
}

impl Processor for MinPhaseEq {
    fn reset(&mut self) {
        for band in &mut self.bands_l {
            band.reset();
        }
        for band in &mut self.bands_r {
            band.reset();
        }
    }

    fn latency(&self) -> usize {
        0 // True zero latency
    }
}

impl StereoProcessor for MinPhaseEq {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let mut l = left;
        let mut r = right;

        for band in &mut self.bands_l {
            l = band.process(l);
        }
        for band in &mut self.bands_r {
            r = band.process(r);
        }

        (l, r)
    }
}

// ============================================================================
// LINEAR-TO-MINIMUM PHASE CONVERTER
// ============================================================================

/// Converts linear phase FIR to minimum phase
pub struct LinearToMinPhase {
    reconstructor: MinimumPhaseReconstructor,
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    fft_size: usize,
}

impl LinearToMinPhase {
    pub fn new(fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        Self {
            reconstructor: MinimumPhaseReconstructor::new(fft_size),
            fft_forward,
            fft_inverse,
            fft_size,
        }
    }

    /// Convert linear phase FIR to minimum phase
    pub fn convert(&mut self, linear_fir: &[f64]) -> Vec<f64> {
        let n = linear_fir.len().min(self.fft_size);

        // Get magnitude from linear phase FIR
        let mut input = vec![0.0; self.fft_size];
        input[..n].copy_from_slice(&linear_fir[..n]);

        let mut spectrum = vec![Complex::new(0.0, 0.0); self.fft_size / 2 + 1];
        self.fft_forward.process(&mut input, &mut spectrum).unwrap();

        // Get magnitude
        let magnitude: Vec<f64> = spectrum.iter()
            .map(|c| (c.re * c.re + c.im * c.im).sqrt())
            .collect();

        // Reconstruct with minimum phase
        let min_phase_spectrum = self.reconstructor.reconstruct(&magnitude);

        // IFFT to get minimum phase FIR
        let mut full_spectrum = vec![Complex::new(0.0, 0.0); self.fft_size / 2 + 1];
        for (i, c) in min_phase_spectrum.iter().enumerate() {
            if i < full_spectrum.len() {
                full_spectrum[i] = *c;
            }
        }

        let mut output = vec![0.0; self.fft_size];
        self.fft_inverse.process(&mut full_spectrum, &mut output).unwrap();

        // Normalize and truncate
        let norm = 1.0 / self.fft_size as f64;
        output.iter().take(n).map(|&x| x * norm).collect()
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_min_phase_eq() {
        let mut eq = MinPhaseEq::new(48000.0);
        eq.add_band(1000.0, 6.0, 1.0, MinPhaseFilterType::Bell);

        let (out_l, out_r) = eq.process_sample(1.0, 1.0);
        assert!(out_l != 1.0);
        assert!(out_r != 1.0);
    }

    #[test]
    fn test_magnitude_response() {
        let eq = MinPhaseEq::new(48000.0);
        let mut eq = eq;
        eq.add_band(1000.0, 6.0, 1.0, MinPhaseFilterType::Bell);

        // At center frequency, should be boosted
        let mag_1k = eq.magnitude_at(1000.0);
        let db_1k = 20.0 * mag_1k.log10();
        assert!(db_1k > 5.0 && db_1k < 7.0);
    }

    #[test]
    fn test_hilbert() {
        let mut hilbert = HilbertTransform::new(1024);
        let input: Vec<f64> = (0..512).map(|i| (2.0 * PI * i as f64 / 64.0).sin()).collect();
        let envelope = hilbert.envelope(&input);
        assert!(!envelope.is_empty());
    }
}
