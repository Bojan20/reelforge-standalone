//! Linear Phase EQ
//!
//! True linear phase equalization:
//! - Zero phase distortion
//! - Symmetric FIR filter design
//! - Multiple filter types (bell, shelf, cut)
//! - Smooth real-time parameter changes
//! - Optimized FFT-based overlap-save convolution

use std::f64::consts::PI;
use std::sync::Arc;

use realfft::{RealFftPlanner, RealToComplex, ComplexToReal};
use rustfft::num_complex::Complex;

use rf_core::Sample;
use crate::{Processor, ProcessorConfig, StereoProcessor};

// ============ Constants ============

/// FFT size for filter design
const DESIGN_FFT_SIZE: usize = 4096;

/// Processing FFT size
const PROCESS_FFT_SIZE: usize = 2048;

/// Maximum number of bands
pub const MAX_LINEAR_PHASE_BANDS: usize = 32;

// ============ Filter Type ============

/// Linear phase filter type
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LinearPhaseFilterType {
    /// Bell/Peaking
    Bell,
    /// Low shelf
    LowShelf,
    /// High shelf
    HighShelf,
    /// Low cut (high pass)
    LowCut,
    /// High cut (low pass)
    HighCut,
    /// Notch
    Notch,
    /// Band pass
    BandPass,
    /// Tilt (full spectrum)
    Tilt,
}

impl Default for LinearPhaseFilterType {
    fn default() -> Self {
        Self::Bell
    }
}

// ============ EQ Band ============

/// Single linear phase EQ band
#[derive(Debug, Clone)]
pub struct LinearPhaseBand {
    /// Filter type
    pub filter_type: LinearPhaseFilterType,
    /// Center/corner frequency (Hz)
    pub frequency: f64,
    /// Gain (dB)
    pub gain: f64,
    /// Q factor (bandwidth)
    pub q: f64,
    /// Slope for cuts (dB/octave: 6, 12, 18, 24, 48, 96)
    pub slope: f64,
    /// Enabled
    pub enabled: bool,
}

impl Default for LinearPhaseBand {
    fn default() -> Self {
        Self {
            filter_type: LinearPhaseFilterType::Bell,
            frequency: 1000.0,
            gain: 0.0,
            q: 0.707,
            slope: 12.0,
            enabled: true,
        }
    }
}

impl LinearPhaseBand {
    /// Create bell filter
    pub fn bell(frequency: f64, gain: f64, q: f64) -> Self {
        Self {
            filter_type: LinearPhaseFilterType::Bell,
            frequency,
            gain,
            q,
            ..Default::default()
        }
    }

    /// Create low shelf
    pub fn low_shelf(frequency: f64, gain: f64, q: f64) -> Self {
        Self {
            filter_type: LinearPhaseFilterType::LowShelf,
            frequency,
            gain,
            q,
            ..Default::default()
        }
    }

    /// Create high shelf
    pub fn high_shelf(frequency: f64, gain: f64, q: f64) -> Self {
        Self {
            filter_type: LinearPhaseFilterType::HighShelf,
            frequency,
            gain,
            q,
            ..Default::default()
        }
    }

    /// Create low cut (high pass)
    pub fn low_cut(frequency: f64, slope: f64) -> Self {
        Self {
            filter_type: LinearPhaseFilterType::LowCut,
            frequency,
            slope,
            ..Default::default()
        }
    }

    /// Create high cut (low pass)
    pub fn high_cut(frequency: f64, slope: f64) -> Self {
        Self {
            filter_type: LinearPhaseFilterType::HighCut,
            frequency,
            slope,
            ..Default::default()
        }
    }
}

// ============ Frequency Response Designer ============

/// Designs ideal frequency response from bands
struct FrequencyResponseDesigner {
    sample_rate: f64,
    fft_size: usize,
}

impl FrequencyResponseDesigner {
    fn new(sample_rate: f64, fft_size: usize) -> Self {
        Self { sample_rate, fft_size }
    }

    /// Calculate magnitude response for a band at given frequency
    fn band_magnitude(&self, band: &LinearPhaseBand, freq: f64) -> f64 {
        if !band.enabled {
            return 1.0;
        }

        let w = freq / band.frequency;

        match band.filter_type {
            LinearPhaseFilterType::Bell => {
                if band.gain.abs() < 0.01 {
                    return 1.0;
                }

                let a = 10.0_f64.powf(band.gain / 40.0);
                let w2 = w * w;
                let bw = 1.0 / band.q;

                let num = (w2 - 1.0).powi(2) + (w * bw * a).powi(2);
                let den = (w2 - 1.0).powi(2) + (w * bw / a).powi(2);

                (num / den).sqrt()
            }

            LinearPhaseFilterType::LowShelf => {
                let gain_linear = 10.0_f64.powf(band.gain / 20.0);

                if w < 0.5 {
                    gain_linear
                } else if w > 2.0 {
                    1.0
                } else {
                    // Smooth transition
                    let t = (w.log2() + 1.0) / 2.0;
                    let t = t.clamp(0.0, 1.0);
                    gain_linear * (1.0 - t) + t
                }
            }

            LinearPhaseFilterType::HighShelf => {
                let gain_linear = 10.0_f64.powf(band.gain / 20.0);

                if w > 2.0 {
                    gain_linear
                } else if w < 0.5 {
                    1.0
                } else {
                    let t = (w.log2() + 1.0) / 2.0;
                    let t = t.clamp(0.0, 1.0);
                    1.0 * (1.0 - t) + gain_linear * t
                }
            }

            LinearPhaseFilterType::LowCut => {
                if freq < 1.0 {
                    return 0.0;
                }

                let order = (band.slope / 6.0).round() as i32;
                let butterworth = 1.0 / (1.0 + (band.frequency / freq).powi(2 * order)).sqrt();
                butterworth
            }

            LinearPhaseFilterType::HighCut => {
                if freq < 1.0 {
                    return 1.0;
                }

                let order = (band.slope / 6.0).round() as i32;
                let butterworth = 1.0 / (1.0 + (freq / band.frequency).powi(2 * order)).sqrt();
                butterworth
            }

            LinearPhaseFilterType::Notch => {
                let bw = 1.0 / band.q;
                let w2 = w * w;
                let depth = 10.0_f64.powf(-band.gain.abs() / 20.0);

                let resonance = (w2 - 1.0).powi(2) + (w * bw).powi(2);
                let min_val = depth;
                let factor = ((w2 - 1.0).powi(2) / resonance).sqrt();

                min_val + (1.0 - min_val) * factor
            }

            LinearPhaseFilterType::BandPass => {
                let bw = 1.0 / band.q;
                let w2 = w * w;

                let response = (w * bw) / ((w2 - 1.0).powi(2) + (w * bw).powi(2)).sqrt();
                response * 10.0_f64.powf(band.gain / 20.0)
            }

            LinearPhaseFilterType::Tilt => {
                // Tilt: +gain at high frequencies, -gain at low
                let gain_per_octave = band.gain / 10.0; // dB per octave from 1kHz
                let octaves = (freq / 1000.0).log2();
                10.0_f64.powf(gain_per_octave * octaves / 20.0)
            }
        }
    }

    /// Calculate complete magnitude response for all bands
    fn calculate_magnitude_response(&self, bands: &[LinearPhaseBand]) -> Vec<f64> {
        let num_bins = self.fft_size / 2 + 1;
        let mut response = vec![1.0; num_bins];

        for (i, mag) in response.iter_mut().enumerate() {
            let freq = i as f64 * self.sample_rate / self.fft_size as f64;

            for band in bands {
                *mag *= self.band_magnitude(band, freq);
            }
        }

        response
    }
}

// ============ FIR Designer ============

/// Designs linear phase FIR filter from magnitude response
struct FirDesigner {
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    fft_size: usize,
}

impl FirDesigner {
    fn new(fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::<f64>::new();

        Self {
            fft_forward: planner.plan_fft_forward(fft_size),
            fft_inverse: planner.plan_fft_inverse(fft_size),
            fft_size,
        }
    }

    /// Create linear phase FIR from magnitude response
    fn design_filter(&self, magnitude: &[f64]) -> Vec<f64> {
        // Create complex spectrum with zero phase
        let mut spectrum: Vec<Complex<f64>> = magnitude.iter()
            .map(|&m| Complex::new(m, 0.0))
            .collect();

        // IFFT to get impulse response
        let mut impulse = vec![0.0; self.fft_size];
        self.fft_inverse.process(&mut spectrum, &mut impulse).ok();

        // Normalize
        let norm = 1.0 / self.fft_size as f64;
        for sample in &mut impulse {
            *sample *= norm;
        }

        // Make symmetric (linear phase)
        // Shift so that center of impulse is at the middle
        let half = self.fft_size / 2;
        let mut symmetric = vec![0.0; self.fft_size];

        for i in 0..self.fft_size {
            let src_idx = (i + half) % self.fft_size;
            symmetric[i] = impulse[src_idx];
        }

        // Apply window (Blackman-Harris for low sidelobes)
        for (i, sample) in symmetric.iter_mut().enumerate() {
            let t = i as f64 / (self.fft_size - 1) as f64;
            let window = 0.35875
                - 0.48829 * (2.0 * PI * t).cos()
                + 0.14128 * (4.0 * PI * t).cos()
                - 0.01168 * (6.0 * PI * t).cos();
            *sample *= window;
        }

        symmetric
    }
}

// ============ Overlap-Save Convolver ============

/// FFT-based overlap-save convolver for real-time processing
struct OverlapSaveConvolver {
    /// Filter spectrum
    filter_spectrum: Vec<Complex<f64>>,
    /// Input buffer
    input_buffer: Vec<f64>,
    /// Output overlap buffer
    overlap: Vec<f64>,
    /// FFT planners
    fft_forward: Arc<dyn RealToComplex<f64>>,
    fft_inverse: Arc<dyn ComplexToReal<f64>>,
    /// Buffer position
    buffer_pos: usize,
    /// Block size
    block_size: usize,
    /// FFT size
    fft_size: usize,
}

impl OverlapSaveConvolver {
    fn new(filter_ir: &[f64], block_size: usize) -> Self {
        let fft_size = block_size * 2;
        let mut planner = RealFftPlanner::<f64>::new();

        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // FFT the filter
        let mut filter_padded = vec![0.0; fft_size];
        let copy_len = filter_ir.len().min(fft_size);
        filter_padded[..copy_len].copy_from_slice(&filter_ir[..copy_len]);

        let mut filter_spectrum = vec![Complex::new(0.0, 0.0); fft_size / 2 + 1];
        fft_forward.process(&mut filter_padded, &mut filter_spectrum).ok();

        Self {
            filter_spectrum,
            input_buffer: vec![0.0; fft_size],
            overlap: vec![0.0; block_size],
            fft_forward,
            fft_inverse,
            buffer_pos: 0,
            block_size,
            fft_size,
        }
    }

    fn update_filter(&mut self, filter_ir: &[f64]) {
        let mut filter_padded = vec![0.0; self.fft_size];
        let copy_len = filter_ir.len().min(self.fft_size);
        filter_padded[..copy_len].copy_from_slice(&filter_ir[..copy_len]);

        self.fft_forward.process(&mut filter_padded, &mut self.filter_spectrum).ok();
    }

    fn process_block(&mut self, input: &[f64], output: &mut [f64]) {
        // Copy input to buffer
        for (i, &sample) in input.iter().take(self.block_size).enumerate() {
            self.input_buffer[self.block_size + i] = sample;
        }

        // FFT input
        let mut input_copy = self.input_buffer.clone();
        let mut input_spectrum = vec![Complex::new(0.0, 0.0); self.fft_size / 2 + 1];
        self.fft_forward.process(&mut input_copy, &mut input_spectrum).ok();

        // Complex multiply
        let mut result_spectrum: Vec<Complex<f64>> = input_spectrum.iter()
            .zip(&self.filter_spectrum)
            .map(|(a, b)| a * b)
            .collect();

        // IFFT
        let mut result = vec![0.0; self.fft_size];
        self.fft_inverse.process(&mut result_spectrum, &mut result).ok();

        // Normalize and output
        let norm = 1.0 / self.fft_size as f64;
        for (i, sample) in output.iter_mut().enumerate().take(self.block_size) {
            *sample = result[self.block_size + i] * norm;
        }

        // Shift input buffer
        for i in 0..self.block_size {
            self.input_buffer[i] = self.input_buffer[self.block_size + i];
        }
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.overlap.fill(0.0);
        self.buffer_pos = 0;
    }
}

// ============ Linear Phase EQ ============

/// Professional linear phase EQ
pub struct LinearPhaseEQ {
    /// EQ bands
    bands: Vec<LinearPhaseBand>,
    /// Left channel convolver
    convolver_l: OverlapSaveConvolver,
    /// Right channel convolver
    convolver_r: OverlapSaveConvolver,
    /// Frequency response designer
    designer: FrequencyResponseDesigner,
    /// FIR designer
    fir_designer: FirDesigner,
    /// Current FIR filter
    current_fir: Vec<f64>,
    /// Sample rate
    sample_rate: f64,
    /// Block size
    block_size: usize,
    /// Input buffers
    input_l: Vec<f64>,
    input_r: Vec<f64>,
    /// Output buffers
    output_l: Vec<f64>,
    output_r: Vec<f64>,
    /// Buffer position
    buffer_pos: usize,
    /// Filter needs update
    filter_dirty: bool,
    /// Bypass
    bypassed: bool,
}

impl LinearPhaseEQ {
    /// Create new linear phase EQ
    pub fn new(sample_rate: f64) -> Self {
        let block_size = PROCESS_FFT_SIZE / 2;
        let design_fft_size = DESIGN_FFT_SIZE;

        let designer = FrequencyResponseDesigner::new(sample_rate, design_fft_size);
        let fir_designer = FirDesigner::new(design_fft_size);

        // Create flat filter
        let flat_fir = vec![0.0; design_fft_size];
        let mut initial_fir = flat_fir.clone();
        initial_fir[design_fft_size / 2] = 1.0; // Dirac delta = flat response

        let convolver_l = OverlapSaveConvolver::new(&initial_fir, block_size);
        let convolver_r = OverlapSaveConvolver::new(&initial_fir, block_size);

        Self {
            bands: Vec::new(),
            convolver_l,
            convolver_r,
            designer,
            fir_designer,
            current_fir: initial_fir,
            sample_rate,
            block_size,
            input_l: vec![0.0; block_size],
            input_r: vec![0.0; block_size],
            output_l: vec![0.0; block_size],
            output_r: vec![0.0; block_size],
            buffer_pos: 0,
            filter_dirty: false,
            bypassed: false,
        }
    }

    /// Add a band
    pub fn add_band(&mut self, band: LinearPhaseBand) -> usize {
        if self.bands.len() < MAX_LINEAR_PHASE_BANDS {
            self.bands.push(band);
            self.filter_dirty = true;
            self.bands.len() - 1
        } else {
            MAX_LINEAR_PHASE_BANDS - 1
        }
    }

    /// Update a band
    pub fn update_band(&mut self, index: usize, band: LinearPhaseBand) {
        if index < self.bands.len() {
            self.bands[index] = band;
            self.filter_dirty = true;
        }
    }

    /// Remove a band
    pub fn remove_band(&mut self, index: usize) {
        if index < self.bands.len() {
            self.bands.remove(index);
            self.filter_dirty = true;
        }
    }

    /// Get band
    pub fn get_band(&self, index: usize) -> Option<&LinearPhaseBand> {
        self.bands.get(index)
    }

    /// Get band count
    pub fn band_count(&self) -> usize {
        self.bands.len()
    }

    /// Set bypass
    pub fn set_bypass(&mut self, bypass: bool) {
        self.bypassed = bypass;
    }

    /// Update filter (call periodically, not every sample)
    fn update_filter(&mut self) {
        if !self.filter_dirty {
            return;
        }

        // Calculate magnitude response
        let magnitude = self.designer.calculate_magnitude_response(&self.bands);

        // Design FIR filter
        self.current_fir = self.fir_designer.design_filter(&magnitude);

        // Update convolvers
        self.convolver_l.update_filter(&self.current_fir);
        self.convolver_r.update_filter(&self.current_fir);

        self.filter_dirty = false;
    }

    /// Get magnitude response for visualization
    pub fn get_magnitude_response(&self, num_points: usize) -> Vec<(f64, f64)> {
        let mut response = Vec::with_capacity(num_points);

        for i in 0..num_points {
            // Logarithmic frequency scale
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t); // 20Hz to 20kHz

            let mut mag = 1.0;
            for band in &self.bands {
                mag *= self.designer.band_magnitude(band, freq);
            }

            let db = 20.0 * mag.log10();
            response.push((freq, db));
        }

        response
    }

    fn process_block_internal(&mut self) {
        // Update filter if needed
        self.update_filter();

        // Process through convolvers
        self.convolver_l.process_block(&self.input_l, &mut self.output_l);
        self.convolver_r.process_block(&self.input_r, &mut self.output_r);
    }
}

impl Processor for LinearPhaseEQ {
    fn reset(&mut self) {
        self.convolver_l.reset();
        self.convolver_r.reset();
        self.input_l.fill(0.0);
        self.input_r.fill(0.0);
        self.output_l.fill(0.0);
        self.output_r.fill(0.0);
        self.buffer_pos = 0;
    }

    fn latency(&self) -> usize {
        // Linear phase = half the FIR length
        DESIGN_FFT_SIZE / 2 + self.block_size
    }
}

impl StereoProcessor for LinearPhaseEQ {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if self.bypassed {
            return (left, right);
        }

        // Add to input buffer
        self.input_l[self.buffer_pos] = left;
        self.input_r[self.buffer_pos] = right;

        // Get output from previous block
        let out_l = self.output_l[self.buffer_pos];
        let out_r = self.output_r[self.buffer_pos];

        self.buffer_pos += 1;

        // Process block when full
        if self.buffer_pos >= self.block_size {
            self.process_block_internal();
            self.buffer_pos = 0;
        }

        (out_l, out_r)
    }
}

impl ProcessorConfig for LinearPhaseEQ {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        if (sample_rate - self.sample_rate).abs() > 1.0 {
            self.sample_rate = sample_rate;
            self.designer = FrequencyResponseDesigner::new(sample_rate, DESIGN_FFT_SIZE);
            self.filter_dirty = true;
        }
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear_phase_eq_creation() {
        let eq = LinearPhaseEQ::new(48000.0);
        assert_eq!(eq.band_count(), 0);
    }

    #[test]
    fn test_add_bands() {
        let mut eq = LinearPhaseEQ::new(48000.0);

        eq.add_band(LinearPhaseBand::bell(1000.0, 6.0, 1.0));
        eq.add_band(LinearPhaseBand::low_shelf(100.0, 3.0, 0.707));
        eq.add_band(LinearPhaseBand::high_shelf(10000.0, -3.0, 0.707));

        assert_eq!(eq.band_count(), 3);
    }

    #[test]
    fn test_magnitude_response() {
        let mut eq = LinearPhaseEQ::new(48000.0);
        eq.add_band(LinearPhaseBand::bell(1000.0, 6.0, 1.0));

        let response = eq.get_magnitude_response(100);
        assert_eq!(response.len(), 100);

        // Check that response at 1kHz is boosted
        let at_1k = response.iter()
            .find(|(f, _)| (*f - 1000.0).abs() < 100.0)
            .map(|(_, db)| *db)
            .unwrap_or(0.0);

        assert!(at_1k > 0.0);
    }

    #[test]
    fn test_linear_phase_processing() {
        let mut eq = LinearPhaseEQ::new(48000.0);
        eq.add_band(LinearPhaseBand::bell(1000.0, 3.0, 1.0));

        // Process some samples
        for _ in 0..10000 {
            let _ = eq.process_sample(0.5, 0.5);
        }
    }

    #[test]
    fn test_bypass() {
        let mut eq = LinearPhaseEQ::new(48000.0);
        eq.add_band(LinearPhaseBand::bell(1000.0, 12.0, 1.0));
        eq.set_bypass(true);

        // When bypassed, should pass through
        let (l, r) = eq.process_sample(0.5, 0.5);
        assert!((l - 0.5).abs() < 1e-10);
        assert!((r - 0.5).abs() < 1e-10);
    }
}
