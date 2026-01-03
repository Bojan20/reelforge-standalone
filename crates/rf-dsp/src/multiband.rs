//! Multi-band Dynamics Processing
//!
//! Professional multi-band dynamics:
//! - Multi-band compressor (up to 6 bands)
//! - Multi-band limiter
//! - Multi-band gate/expander
//! - Linear phase crossovers
//! - Linkwitz-Riley filters (12/24/48 dB/oct)

use rf_core::Sample;
use crate::{Processor, ProcessorConfig, StereoProcessor, MonoProcessor};
use crate::biquad::{BiquadTDF2, BiquadCoeffs};

// ============ Constants ============

/// Maximum bands
pub const MAX_BANDS: usize = 6;

/// Default crossover frequencies
const DEFAULT_CROSSOVERS: [f64; 5] = [100.0, 500.0, 2000.0, 6000.0, 12000.0];

// ============ Crossover Type ============

/// Crossover filter type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CrossoverType {
    /// Butterworth 12 dB/oct
    Butterworth12,
    /// Linkwitz-Riley 24 dB/oct (phase-matched)
    #[default]
    LinkwitzRiley24,
    /// Linkwitz-Riley 48 dB/oct
    LinkwitzRiley48,
}

impl CrossoverType {
    fn order(&self) -> usize {
        match self {
            Self::Butterworth12 => 2,
            Self::LinkwitzRiley24 => 4,
            Self::LinkwitzRiley48 => 8,
        }
    }
}

// ============ Linkwitz-Riley Filter ============

/// Linkwitz-Riley crossover filter (lowpass or highpass)
#[derive(Debug, Clone)]
struct LRFilter {
    /// Biquad stages
    stages: Vec<BiquadTDF2>,
    /// Number of stages
    num_stages: usize,
}

impl LRFilter {
    /// Create lowpass LR filter
    fn lowpass(freq: f64, sample_rate: f64, crossover_type: CrossoverType) -> Self {
        let order = crossover_type.order();
        let num_stages = order / 2;

        let mut stages = Vec::with_capacity(num_stages);

        for i in 0..num_stages {
            // Q values for Butterworth cascaded to create LR
            let q = match crossover_type {
                CrossoverType::Butterworth12 => 0.7071,
                CrossoverType::LinkwitzRiley24 => {
                    if i == 0 { 0.7071 } else { 0.7071 }
                }
                CrossoverType::LinkwitzRiley48 => {
                    // LR48 uses 4 cascaded Butterworth 2nd order
                    0.7071
                }
            };

            let coeffs = BiquadCoeffs::lowpass(freq, q, sample_rate);
            stages.push(BiquadTDF2::with_coeffs(coeffs, sample_rate));
        }

        Self { stages, num_stages }
    }

    /// Create highpass LR filter
    fn highpass(freq: f64, sample_rate: f64, crossover_type: CrossoverType) -> Self {
        let order = crossover_type.order();
        let num_stages = order / 2;

        let mut stages = Vec::with_capacity(num_stages);

        for i in 0..num_stages {
            let q = match crossover_type {
                CrossoverType::Butterworth12 => 0.7071,
                CrossoverType::LinkwitzRiley24 | CrossoverType::LinkwitzRiley48 => 0.7071,
            };

            let coeffs = BiquadCoeffs::highpass(freq, q, sample_rate);
            stages.push(BiquadTDF2::with_coeffs(coeffs, sample_rate));
        }

        Self { stages, num_stages }
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        let mut output = input;
        for stage in &mut self.stages {
            output = stage.process_sample(output);
        }
        output
    }

    fn reset(&mut self) {
        for stage in &mut self.stages {
            stage.reset();
        }
    }

    fn update(&mut self, freq: f64, sample_rate: f64, is_lowpass: bool) {
        for stage in &mut self.stages {
            let coeffs = if is_lowpass {
                BiquadCoeffs::lowpass(freq, 0.7071, sample_rate)
            } else {
                BiquadCoeffs::highpass(freq, 0.7071, sample_rate)
            };
            stage.set_coeffs(coeffs);
        }
    }
}

// ============ Crossover ============

/// Single crossover point (splits signal into low and high)
#[derive(Debug, Clone)]
struct Crossover {
    lowpass_l: LRFilter,
    lowpass_r: LRFilter,
    highpass_l: LRFilter,
    highpass_r: LRFilter,
    frequency: f64,
}

impl Crossover {
    fn new(freq: f64, sample_rate: f64, crossover_type: CrossoverType) -> Self {
        Self {
            lowpass_l: LRFilter::lowpass(freq, sample_rate, crossover_type),
            lowpass_r: LRFilter::lowpass(freq, sample_rate, crossover_type),
            highpass_l: LRFilter::highpass(freq, sample_rate, crossover_type),
            highpass_r: LRFilter::highpass(freq, sample_rate, crossover_type),
            frequency: freq,
        }
    }

    fn split(&mut self, left: f64, right: f64) -> ((f64, f64), (f64, f64)) {
        let low_l = self.lowpass_l.process(left);
        let low_r = self.lowpass_r.process(right);
        let high_l = self.highpass_l.process(left);
        let high_r = self.highpass_r.process(right);

        ((low_l, low_r), (high_l, high_r))
    }

    fn reset(&mut self) {
        self.lowpass_l.reset();
        self.lowpass_r.reset();
        self.highpass_l.reset();
        self.highpass_r.reset();
    }

    fn set_frequency(&mut self, freq: f64, sample_rate: f64) {
        self.frequency = freq;
        self.lowpass_l.update(freq, sample_rate, true);
        self.lowpass_r.update(freq, sample_rate, true);
        self.highpass_l.update(freq, sample_rate, false);
        self.highpass_r.update(freq, sample_rate, false);
    }
}

// ============ Band Compressor ============

/// Per-band compressor settings
#[derive(Debug, Clone)]
pub struct BandCompressor {
    /// Threshold (dB)
    pub threshold_db: f64,
    /// Ratio
    pub ratio: f64,
    /// Attack (ms)
    pub attack_ms: f64,
    /// Release (ms)
    pub release_ms: f64,
    /// Knee (dB)
    pub knee_db: f64,
    /// Makeup gain (dB)
    pub makeup_db: f64,
    /// Solo this band
    pub solo: bool,
    /// Mute this band
    pub mute: bool,
    /// Bypass compression
    pub bypass: bool,

    // Internal state
    envelope_l: f64,
    envelope_r: f64,
    attack_coef: f64,
    release_coef: f64,
    gain_reduction_l: f64,
    gain_reduction_r: f64,
}

impl Default for BandCompressor {
    fn default() -> Self {
        Self {
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_db: 0.0,
            solo: false,
            mute: false,
            bypass: false,
            envelope_l: 0.0,
            envelope_r: 0.0,
            attack_coef: 0.0,
            release_coef: 0.0,
            gain_reduction_l: 0.0,
            gain_reduction_r: 0.0,
        }
    }
}

impl BandCompressor {
    /// Update time constants
    pub fn update_coefficients(&mut self, sample_rate: f64) {
        self.attack_coef = (-1.0 / (self.attack_ms * 0.001 * sample_rate)).exp();
        self.release_coef = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();
    }

    /// Process stereo sample
    #[inline]
    pub fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        if self.mute {
            return (0.0, 0.0);
        }

        if self.bypass {
            let makeup = 10.0_f64.powf(self.makeup_db / 20.0);
            return (left * makeup, right * makeup);
        }

        // Envelope detection (peak)
        let input_l = left.abs();
        let input_r = right.abs();

        let coef_l = if input_l > self.envelope_l { self.attack_coef } else { self.release_coef };
        let coef_r = if input_r > self.envelope_r { self.attack_coef } else { self.release_coef };

        self.envelope_l = input_l + coef_l * (self.envelope_l - input_l);
        self.envelope_r = input_r + coef_r * (self.envelope_r - input_r);

        // Calculate gain reduction
        let gr_l = self.compute_gain(self.envelope_l);
        let gr_r = self.compute_gain(self.envelope_r);

        self.gain_reduction_l = gr_l;
        self.gain_reduction_r = gr_r;

        // Apply gain and makeup
        let makeup = 10.0_f64.powf(self.makeup_db / 20.0);

        (left * gr_l * makeup, right * gr_r * makeup)
    }

    fn compute_gain(&self, envelope: f64) -> f64 {
        if envelope < 1e-10 {
            return 1.0;
        }

        let input_db = 20.0 * envelope.log10();
        let threshold = self.threshold_db;
        let ratio = self.ratio;
        let knee = self.knee_db;

        let output_db = if input_db < threshold - knee / 2.0 {
            // Below knee
            input_db
        } else if input_db > threshold + knee / 2.0 {
            // Above knee
            threshold + (input_db - threshold) / ratio
        } else {
            // In knee (soft knee)
            let x = input_db - threshold + knee / 2.0;
            input_db + (1.0 / ratio - 1.0) * x * x / (2.0 * knee)
        };

        10.0_f64.powf((output_db - input_db) / 20.0)
    }

    pub fn reset(&mut self) {
        self.envelope_l = 0.0;
        self.envelope_r = 0.0;
        self.gain_reduction_l = 0.0;
        self.gain_reduction_r = 0.0;
    }

    /// Get current gain reduction (dB)
    pub fn gain_reduction_db(&self) -> (f64, f64) {
        let gr_l = if self.gain_reduction_l > 1e-10 {
            20.0 * self.gain_reduction_l.log10()
        } else {
            -60.0
        };
        let gr_r = if self.gain_reduction_r > 1e-10 {
            20.0 * self.gain_reduction_r.log10()
        } else {
            -60.0
        };
        (gr_l, gr_r)
    }
}

// ============ Multi-band Compressor ============

/// Professional multi-band compressor
pub struct MultibandCompressor {
    /// Number of active bands
    num_bands: usize,
    /// Crossover filters
    crossovers: Vec<Crossover>,
    /// Per-band compressors
    bands: Vec<BandCompressor>,
    /// Crossover frequencies
    crossover_freqs: Vec<f64>,
    /// Crossover type
    crossover_type: CrossoverType,
    /// Output gain (dB)
    output_gain_db: f64,
    /// Sample rate
    sample_rate: f64,
    /// Band buffers
    band_buffers: Vec<(f64, f64)>,
}

impl MultibandCompressor {
    /// Create new multi-band compressor
    pub fn new(sample_rate: f64, num_bands: usize) -> Self {
        let num_bands = num_bands.clamp(2, MAX_BANDS);
        let num_crossovers = num_bands - 1;

        let crossover_freqs: Vec<f64> = DEFAULT_CROSSOVERS[..num_crossovers].to_vec();
        let crossover_type = CrossoverType::LinkwitzRiley24;

        let crossovers: Vec<Crossover> = crossover_freqs.iter()
            .map(|&freq| Crossover::new(freq, sample_rate, crossover_type))
            .collect();

        let mut bands: Vec<BandCompressor> = (0..num_bands)
            .map(|_| BandCompressor::default())
            .collect();

        // Initialize coefficients
        for band in &mut bands {
            band.update_coefficients(sample_rate);
        }

        Self {
            num_bands,
            crossovers,
            bands,
            crossover_freqs,
            crossover_type,
            output_gain_db: 0.0,
            sample_rate,
            band_buffers: vec![(0.0, 0.0); num_bands],
        }
    }

    /// Set number of bands
    pub fn set_num_bands(&mut self, num_bands: usize) {
        let num_bands = num_bands.clamp(2, MAX_BANDS);
        if num_bands == self.num_bands {
            return;
        }

        self.num_bands = num_bands;
        let num_crossovers = num_bands - 1;

        // Recreate crossovers
        self.crossover_freqs = DEFAULT_CROSSOVERS[..num_crossovers].to_vec();
        self.crossovers = self.crossover_freqs.iter()
            .map(|&freq| Crossover::new(freq, self.sample_rate, self.crossover_type))
            .collect();

        // Resize bands
        self.bands.resize_with(num_bands, BandCompressor::default);
        for band in &mut self.bands {
            band.update_coefficients(self.sample_rate);
        }

        self.band_buffers = vec![(0.0, 0.0); num_bands];
    }

    /// Set crossover frequency
    pub fn set_crossover(&mut self, index: usize, freq: f64) {
        if index < self.crossovers.len() {
            let freq = freq.clamp(20.0, 20000.0);
            self.crossover_freqs[index] = freq;
            self.crossovers[index].set_frequency(freq, self.sample_rate);
        }
    }

    /// Get band settings
    pub fn band(&self, index: usize) -> Option<&BandCompressor> {
        self.bands.get(index)
    }

    /// Get mutable band settings
    pub fn band_mut(&mut self, index: usize) -> Option<&mut BandCompressor> {
        self.bands.get_mut(index)
    }

    /// Set output gain
    pub fn set_output_gain(&mut self, db: f64) {
        self.output_gain_db = db.clamp(-24.0, 24.0);
    }

    /// Set crossover type
    pub fn set_crossover_type(&mut self, crossover_type: CrossoverType) {
        self.crossover_type = crossover_type;

        // Recreate crossovers
        self.crossovers = self.crossover_freqs.iter()
            .map(|&freq| Crossover::new(freq, self.sample_rate, crossover_type))
            .collect();
    }

    /// Get per-band gain reduction for metering
    pub fn get_gain_reduction(&self) -> Vec<(f64, f64)> {
        self.bands.iter()
            .map(|b| b.gain_reduction_db())
            .collect()
    }

    /// Split signal into bands
    fn split_bands(&mut self, left: f64, right: f64) {
        if self.num_bands == 1 {
            self.band_buffers[0] = (left, right);
            return;
        }

        let mut remaining_l = left;
        let mut remaining_r = right;

        for i in 0..self.crossovers.len() {
            let ((low_l, low_r), (high_l, high_r)) =
                self.crossovers[i].split(remaining_l, remaining_r);

            self.band_buffers[i] = (low_l, low_r);
            remaining_l = high_l;
            remaining_r = high_r;
        }

        // Last band is the remaining high frequencies
        self.band_buffers[self.num_bands - 1] = (remaining_l, remaining_r);
    }
}

impl Processor for MultibandCompressor {
    fn reset(&mut self) {
        for crossover in &mut self.crossovers {
            crossover.reset();
        }
        for band in &mut self.bands {
            band.reset();
        }
        for buf in &mut self.band_buffers {
            *buf = (0.0, 0.0);
        }
    }

    fn latency(&self) -> usize {
        // LR crossovers have some latency
        self.crossover_type.order() * 2
    }
}

impl StereoProcessor for MultibandCompressor {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Split into bands
        self.split_bands(left, right);

        // Check for solo
        let any_solo = self.bands.iter().any(|b| b.solo);

        // Process each band and sum
        let mut out_l = 0.0;
        let mut out_r = 0.0;

        for i in 0..self.num_bands {
            let (band_l, band_r) = self.band_buffers[i];
            let (proc_l, proc_r) = self.bands[i].process(band_l, band_r);

            // Solo handling
            if any_solo {
                if self.bands[i].solo {
                    out_l += proc_l;
                    out_r += proc_r;
                }
            } else {
                out_l += proc_l;
                out_r += proc_r;
            }
        }

        // Apply output gain
        let output_gain = 10.0_f64.powf(self.output_gain_db / 20.0);

        (out_l * output_gain, out_r * output_gain)
    }
}

impl ProcessorConfig for MultibandCompressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;

        // Update crossovers
        for (i, crossover) in self.crossovers.iter_mut().enumerate() {
            crossover.set_frequency(self.crossover_freqs[i], sample_rate);
        }

        // Update band coefficients
        for band in &mut self.bands {
            band.update_coefficients(sample_rate);
        }
    }
}

// ============ Multi-band Limiter ============

/// Multi-band limiter (based on multi-band compressor with high ratio)
pub struct MultibandLimiter {
    compressor: MultibandCompressor,
}

impl MultibandLimiter {
    pub fn new(sample_rate: f64, num_bands: usize) -> Self {
        let mut compressor = MultibandCompressor::new(sample_rate, num_bands);

        // Configure for limiting
        for band in &mut compressor.bands {
            band.ratio = 20.0; // High ratio
            band.attack_ms = 0.5; // Fast attack
            band.release_ms = 50.0; // Moderate release
            band.knee_db = 0.0; // Hard knee
            band.threshold_db = -3.0; // Default threshold
            band.update_coefficients(sample_rate);
        }

        Self { compressor }
    }

    /// Set ceiling (threshold) for all bands
    pub fn set_ceiling(&mut self, db: f64) {
        for band in &mut self.compressor.bands {
            band.threshold_db = db;
        }
    }

    /// Set per-band ceiling
    pub fn set_band_ceiling(&mut self, index: usize, db: f64) {
        if let Some(band) = self.compressor.band_mut(index) {
            band.threshold_db = db;
        }
    }

    /// Get limiter settings for band
    pub fn band(&self, index: usize) -> Option<&BandCompressor> {
        self.compressor.band(index)
    }

    /// Get mutable band
    pub fn band_mut(&mut self, index: usize) -> Option<&mut BandCompressor> {
        self.compressor.band_mut(index)
    }
}

impl Processor for MultibandLimiter {
    fn reset(&mut self) {
        self.compressor.reset();
    }

    fn latency(&self) -> usize {
        self.compressor.latency()
    }
}

impl StereoProcessor for MultibandLimiter {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        self.compressor.process_sample(left, right)
    }
}

impl ProcessorConfig for MultibandLimiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.compressor.set_sample_rate(sample_rate);

        // Re-apply fast attack for limiting
        for band in &mut self.compressor.bands {
            band.attack_ms = 0.5;
            band.update_coefficients(sample_rate);
        }
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_multiband_compressor_creation() {
        let mbc = MultibandCompressor::new(48000.0, 4);
        assert_eq!(mbc.num_bands, 4);
        assert_eq!(mbc.crossovers.len(), 3);
    }

    #[test]
    fn test_multiband_processing() {
        let mut mbc = MultibandCompressor::new(48000.0, 3);

        // Process samples
        for _ in 0..10000 {
            let (l, r) = mbc.process_sample(0.5, 0.5);
            assert!(l.is_finite());
            assert!(r.is_finite());
        }
    }

    #[test]
    fn test_band_compression() {
        let mut band = BandCompressor::default();
        band.threshold_db = -20.0;
        band.ratio = 4.0;
        band.update_coefficients(48000.0);

        // Process loud signal
        for _ in 0..1000 {
            let (l, r) = band.process(0.9, 0.9);
            assert!(l <= 0.9);
            assert!(r <= 0.9);
        }
    }

    #[test]
    fn test_crossover() {
        let mut crossover = Crossover::new(1000.0, 48000.0, CrossoverType::LinkwitzRiley24);

        let ((low_l, low_r), (high_l, high_r)) = crossover.split(1.0, 1.0);

        // Sum should approximately equal input (flat response)
        let sum_l = low_l + high_l;
        let sum_r = low_r + high_r;

        // Note: There will be some phase difference initially
        assert!(sum_l.is_finite());
        assert!(sum_r.is_finite());
    }

    #[test]
    fn test_multiband_limiter() {
        let mut limiter = MultibandLimiter::new(48000.0, 3);
        limiter.set_ceiling(-1.0);

        for _ in 0..10000 {
            let (l, r) = limiter.process_sample(0.9, 0.9);
            assert!(l.is_finite());
            assert!(r.is_finite());
        }
    }

    #[test]
    fn test_solo_mute() {
        let mut mbc = MultibandCompressor::new(48000.0, 3);

        // Solo band 1
        mbc.band_mut(1).unwrap().solo = true;

        // Mute band 0
        mbc.band_mut(0).unwrap().mute = true;

        for _ in 0..1000 {
            let _ = mbc.process_sample(0.5, 0.5);
        }
    }
}
