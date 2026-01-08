//! Multiband dynamics processing for mastering
//!
//! Features:
//! - 4-band dynamics with adjustable crossovers
//! - Per-band compression/expansion
//! - Look-ahead for transparent dynamics
//! - Side-chain filtering
//! - Automatic makeup gain

use crate::error::{MasterError, MasterResult};

/// Multiband dynamics configuration
#[derive(Debug, Clone)]
pub struct MultibandDynamicsConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Crossover frequencies
    pub crossovers: Vec<f32>,
    /// Per-band compression ratio
    pub ratios: Vec<f32>,
    /// Per-band threshold (dB)
    pub thresholds: Vec<f32>,
    /// Attack time (ms)
    pub attack_ms: f32,
    /// Release time (ms)
    pub release_ms: f32,
    /// Lookahead (ms)
    pub lookahead_ms: f32,
    /// Knee width (dB)
    pub knee_db: f32,
    /// Auto makeup gain
    pub auto_makeup: bool,
}

impl Default for MultibandDynamicsConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            crossovers: vec![100.0, 500.0, 2000.0, 8000.0],
            ratios: vec![2.0, 2.5, 3.0, 2.5, 2.0],
            thresholds: vec![-24.0, -20.0, -18.0, -20.0, -22.0],
            attack_ms: 10.0,
            release_ms: 100.0,
            lookahead_ms: 5.0,
            knee_db: 6.0,
            auto_makeup: true,
        }
    }
}

/// Linkwitz-Riley crossover filter
#[derive(Clone)]
struct LRCrossover {
    /// Low band output
    low_l: BiquadState,
    low_r: BiquadState,
    /// High band output
    high_l: BiquadState,
    high_r: BiquadState,
    /// Coefficients
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl LRCrossover {
    fn new(freq: f32, sample_rate: u32) -> Self {
        let omega = 2.0 * std::f64::consts::PI * freq as f64 / sample_rate as f64;
        let cos_omega = omega.cos();
        let sin_omega = omega.sin();
        let alpha = sin_omega / (2.0 * 0.7071); // Q = 0.7071 for Butterworth

        // Lowpass coefficients
        let b0 = (1.0 - cos_omega) / 2.0;
        let b1 = 1.0 - cos_omega;
        let b2 = (1.0 - cos_omega) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_omega;
        let a2 = 1.0 - alpha;

        Self {
            low_l: BiquadState::new(),
            low_r: BiquadState::new(),
            high_l: BiquadState::new(),
            high_r: BiquadState::new(),
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
        }
    }

    fn process(&mut self, left: f32, right: f32) -> ((f32, f32), (f32, f32)) {
        // Lowpass
        let low_l = self
            .low_l
            .process(left as f64, self.b0, self.b1, self.b2, self.a1, self.a2);
        let low_r = self
            .low_r
            .process(right as f64, self.b0, self.b1, self.b2, self.a1, self.a2);

        // Second stage for LR4
        let low_l = self
            .low_l
            .process(low_l, self.b0, self.b1, self.b2, self.a1, self.a2);
        let low_r = self
            .low_r
            .process(low_r, self.b0, self.b1, self.b2, self.a1, self.a2);

        // Highpass = original - lowpass (allpass subtraction)
        let high_l = left as f64 - low_l;
        let high_r = right as f64 - low_r;

        ((low_l as f32, low_r as f32), (high_l as f32, high_r as f32))
    }

    fn reset(&mut self) {
        self.low_l.reset();
        self.low_r.reset();
        self.high_l.reset();
        self.high_r.reset();
    }
}

/// Biquad filter state
#[derive(Clone)]
struct BiquadState {
    z1: f64,
    z2: f64,
}

impl BiquadState {
    fn new() -> Self {
        Self { z1: 0.0, z2: 0.0 }
    }

    fn process(&mut self, input: f64, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) -> f64 {
        let output = b0 * input + self.z1;
        self.z1 = b1 * input - a1 * output + self.z2;
        self.z2 = b2 * input - a2 * output;
        output
    }

    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

/// Single-band compressor
#[derive(Clone)]
struct BandCompressor {
    /// Threshold in dB
    threshold: f32,
    /// Compression ratio
    ratio: f32,
    /// Attack coefficient
    attack_coeff: f64,
    /// Release coefficient
    release_coeff: f64,
    /// Knee width
    knee_db: f32,
    /// Current envelope
    envelope: f64,
    /// Makeup gain
    makeup_gain: f32,
}

impl BandCompressor {
    fn new(
        threshold: f32,
        ratio: f32,
        attack_ms: f32,
        release_ms: f32,
        knee_db: f32,
        sample_rate: u32,
    ) -> Self {
        let attack_coeff = (-1.0 / (attack_ms * sample_rate as f32 / 1000.0)).exp() as f64;
        let release_coeff = (-1.0 / (release_ms * sample_rate as f32 / 1000.0)).exp() as f64;

        Self {
            threshold,
            ratio,
            attack_coeff,
            release_coeff,
            knee_db,
            envelope: 0.0,
            makeup_gain: 0.0,
        }
    }

    fn compute_gain(&self, input_db: f32) -> f32 {
        let knee_half = self.knee_db / 2.0;
        let over_threshold = input_db - self.threshold;

        if over_threshold <= -knee_half {
            // Below knee
            0.0
        } else if over_threshold >= knee_half {
            // Above knee
            (1.0 - 1.0 / self.ratio) * over_threshold
        } else {
            // In knee region (soft knee)
            let knee_factor = (over_threshold + knee_half) / self.knee_db;
            (1.0 - 1.0 / self.ratio) * knee_factor * knee_factor * self.knee_db / 2.0
        }
    }

    fn process(&mut self, input_l: f32, input_r: f32) -> (f32, f32) {
        // Compute peak level
        let peak = input_l.abs().max(input_r.abs());
        let input_db = if peak > 1e-10 {
            20.0 * peak.log10()
        } else {
            -100.0
        };

        // Compute target gain reduction
        let target_gr = self.compute_gain(input_db);

        // Smooth envelope
        let target_env = (-target_gr / 20.0f32).exp() as f64;
        if target_env < self.envelope {
            self.envelope =
                self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * target_env;
        } else {
            self.envelope =
                self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target_env;
        }

        // Apply gain
        let gain = (self.envelope as f32) * 10.0f32.powf(self.makeup_gain / 20.0);
        (input_l * gain, input_r * gain)
    }

    fn set_makeup(&mut self, db: f32) {
        self.makeup_gain = db;
    }

    fn reset(&mut self) {
        self.envelope = 1.0;
    }
}

/// Multiband dynamics processor
pub struct MultibandDynamics {
    /// Configuration
    config: MultibandDynamicsConfig,
    /// Crossover filters
    crossovers: Vec<LRCrossover>,
    /// Band compressors
    compressors: Vec<BandCompressor>,
    /// Lookahead buffers
    lookahead_l: Vec<Vec<f32>>,
    lookahead_r: Vec<Vec<f32>>,
    /// Lookahead positions
    lookahead_pos: usize,
    /// Lookahead size
    lookahead_size: usize,
    /// Number of bands
    num_bands: usize,
}

impl MultibandDynamics {
    /// Create new multiband dynamics processor
    pub fn new(config: MultibandDynamicsConfig) -> Self {
        let num_bands = config.crossovers.len() + 1;
        let lookahead_size = (config.lookahead_ms * config.sample_rate as f32 / 1000.0) as usize;

        let crossovers: Vec<LRCrossover> = config
            .crossovers
            .iter()
            .map(|&freq| LRCrossover::new(freq, config.sample_rate))
            .collect();

        let compressors: Vec<BandCompressor> = (0..num_bands)
            .map(|i| {
                let threshold = *config.thresholds.get(i).unwrap_or(&-20.0);
                let ratio = *config.ratios.get(i).unwrap_or(&2.0);
                BandCompressor::new(
                    threshold,
                    ratio,
                    config.attack_ms,
                    config.release_ms,
                    config.knee_db,
                    config.sample_rate,
                )
            })
            .collect();

        let lookahead_l = vec![vec![0.0f32; lookahead_size.max(1)]; num_bands];
        let lookahead_r = vec![vec![0.0f32; lookahead_size.max(1)]; num_bands];

        Self {
            config,
            crossovers,
            compressors,
            lookahead_l,
            lookahead_r,
            lookahead_pos: 0,
            lookahead_size: lookahead_size.max(1),
            num_bands,
        }
    }

    /// Process stereo sample
    pub fn process_sample(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Split into bands
        let mut bands_l = vec![left];
        let mut bands_r = vec![right];

        for crossover in &mut self.crossovers {
            let last_l = bands_l.pop().unwrap();
            let last_r = bands_r.pop().unwrap();

            let ((low_l, low_r), (high_l, high_r)) = crossover.process(last_l, last_r);

            bands_l.push(low_l);
            bands_l.push(high_l);
            bands_r.push(low_r);
            bands_r.push(high_r);
        }

        // Process each band with compression
        let mut output_l = 0.0f32;
        let mut output_r = 0.0f32;

        for (i, compressor) in self.compressors.iter_mut().enumerate() {
            let band_l = bands_l.get(i).copied().unwrap_or(0.0);
            let band_r = bands_r.get(i).copied().unwrap_or(0.0);

            // Lookahead delay
            let delayed_l = self.lookahead_l[i][self.lookahead_pos];
            let delayed_r = self.lookahead_r[i][self.lookahead_pos];

            self.lookahead_l[i][self.lookahead_pos] = band_l;
            self.lookahead_r[i][self.lookahead_pos] = band_r;

            // Compress
            let (comp_l, comp_r) = compressor.process(delayed_l, delayed_r);

            output_l += comp_l;
            output_r += comp_r;
        }

        self.lookahead_pos = (self.lookahead_pos + 1) % self.lookahead_size;

        (output_l, output_r)
    }

    /// Process buffer
    pub fn process(
        &mut self,
        input_l: &[f32],
        input_r: &[f32],
        output_l: &mut [f32],
        output_r: &mut [f32],
    ) -> MasterResult<()> {
        if input_l.len() != output_l.len() || input_r.len() != output_r.len() {
            return Err(MasterError::BufferMismatch {
                expected: input_l.len(),
                got: output_l.len(),
            });
        }

        for i in 0..input_l.len() {
            let (l, r) = self.process_sample(input_l[i], input_r[i]);
            output_l[i] = l;
            output_r[i] = r;
        }

        Ok(())
    }

    /// Set band threshold
    pub fn set_band_threshold(&mut self, band: usize, threshold_db: f32) {
        if let Some(comp) = self.compressors.get_mut(band) {
            comp.threshold = threshold_db;
        }
    }

    /// Set band ratio
    pub fn set_band_ratio(&mut self, band: usize, ratio: f32) {
        if let Some(comp) = self.compressors.get_mut(band) {
            comp.ratio = ratio;
        }
    }

    /// Set band makeup gain
    pub fn set_band_makeup(&mut self, band: usize, gain_db: f32) {
        if let Some(comp) = self.compressors.get_mut(band) {
            comp.set_makeup(gain_db);
        }
    }

    /// Calculate automatic makeup gains
    pub fn calculate_auto_makeup(&mut self) {
        for comp in &mut self.compressors {
            // Estimate average gain reduction at threshold
            let expected_gr = comp.compute_gain(comp.threshold + 6.0);
            comp.set_makeup(expected_gr * 0.5); // Compensate partially
        }
    }

    /// Reset all state
    pub fn reset(&mut self) {
        for crossover in &mut self.crossovers {
            crossover.reset();
        }
        for comp in &mut self.compressors {
            comp.reset();
        }
        for buffer in &mut self.lookahead_l {
            buffer.fill(0.0);
        }
        for buffer in &mut self.lookahead_r {
            buffer.fill(0.0);
        }
        self.lookahead_pos = 0;
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.lookahead_size
    }
}

/// Single-band mastering compressor with advanced features
pub struct MasteringCompressor {
    /// Threshold (dB)
    threshold: f32,
    /// Ratio
    ratio: f32,
    /// Attack (ms)
    attack_ms: f32,
    /// Release (ms)
    release_ms: f32,
    /// Knee (dB)
    knee_db: f32,
    /// Attack coefficient
    attack_coeff: f64,
    /// Release coefficient
    release_coeff: f64,
    /// Envelope follower
    envelope: f64,
    /// Gain reduction (dB)
    gain_reduction: f32,
    /// Sample rate
    sample_rate: u32,
}

impl MasteringCompressor {
    /// Create new mastering compressor
    pub fn new(sample_rate: u32) -> Self {
        let attack_ms = 10.0;
        let release_ms = 100.0;

        Self {
            threshold: -12.0,
            ratio: 2.0,
            attack_ms,
            release_ms,
            knee_db: 6.0,
            attack_coeff: (-1.0 / (attack_ms * sample_rate as f32 / 1000.0)).exp() as f64,
            release_coeff: (-1.0 / (release_ms * sample_rate as f32 / 1000.0)).exp() as f64,
            envelope: 1.0, // Start at unity gain
            gain_reduction: 0.0,
            sample_rate,
        }
    }

    /// Set threshold
    pub fn set_threshold(&mut self, db: f32) {
        self.threshold = db;
    }

    /// Set ratio
    pub fn set_ratio(&mut self, ratio: f32) {
        self.ratio = ratio.max(1.0);
    }

    /// Set attack time
    pub fn set_attack(&mut self, ms: f32) {
        self.attack_ms = ms;
        self.attack_coeff = (-1.0 / (ms * self.sample_rate as f32 / 1000.0)).exp() as f64;
    }

    /// Set release time
    pub fn set_release(&mut self, ms: f32) {
        self.release_ms = ms;
        self.release_coeff = (-1.0 / (ms * self.sample_rate as f32 / 1000.0)).exp() as f64;
    }

    /// Process stereo sample
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Peak detection
        let peak = left.abs().max(right.abs());
        let input_db = if peak > 1e-10 {
            20.0 * peak.log10()
        } else {
            -100.0
        };

        // Compute gain reduction with soft knee
        let knee_half = self.knee_db / 2.0;
        let over_threshold = input_db - self.threshold;

        let target_gr = if over_threshold <= -knee_half {
            0.0
        } else if over_threshold >= knee_half {
            (1.0 - 1.0 / self.ratio) * over_threshold
        } else {
            let knee_factor = (over_threshold + knee_half) / self.knee_db;
            (1.0 - 1.0 / self.ratio) * knee_factor * knee_factor * self.knee_db / 2.0
        };

        // Envelope following
        let target_env = 10.0f64.powf(-target_gr as f64 / 20.0);
        if target_env < self.envelope {
            self.envelope =
                self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * target_env;
        } else {
            self.envelope =
                self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target_env;
        }

        self.gain_reduction = -20.0 * (self.envelope as f32).log10();

        let gain = self.envelope as f32;
        (left * gain, right * gain)
    }

    /// Get current gain reduction (dB)
    pub fn gain_reduction(&self) -> f32 {
        self.gain_reduction
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.envelope = 1.0;
        self.gain_reduction = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_multiband_creation() {
        let config = MultibandDynamicsConfig::default();
        let dynamics = MultibandDynamics::new(config);
        assert_eq!(dynamics.num_bands, 5);
    }

    #[test]
    fn test_multiband_process() {
        let config = MultibandDynamicsConfig::default();
        let mut dynamics = MultibandDynamics::new(config);

        let input_l = vec![0.5f32; 1024];
        let input_r = vec![0.5f32; 1024];
        let mut output_l = vec![0.0f32; 1024];
        let mut output_r = vec![0.0f32; 1024];

        dynamics
            .process(&input_l, &input_r, &mut output_l, &mut output_r)
            .unwrap();

        // Output should be finite
        assert!(output_l.iter().all(|s| s.is_finite()));
        assert!(output_r.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_mastering_compressor() {
        let mut comp = MasteringCompressor::new(48000);
        comp.set_threshold(-12.0);
        comp.set_ratio(4.0);

        // Process loud signal
        let (l, r) = comp.process(0.8, 0.8);

        // Should be reduced
        assert!(l.abs() < 0.8);
        assert!(r.abs() < 0.8);
    }

    #[test]
    fn test_compressor_below_threshold() {
        let mut comp = MasteringCompressor::new(48000);
        comp.set_threshold(-6.0); // -6 dB threshold
        comp.set_ratio(4.0);

        // Process quiet signal (below threshold) for multiple samples
        // to let envelope settle
        let mut l = 0.0f32;
        let mut r = 0.0f32;
        for _ in 0..1000 {
            let result = comp.process(0.1, 0.1);
            l = result.0;
            r = result.1;
        }

        // Should be close to input
        assert!((l - 0.1).abs() < 0.02, "L was {}", l);
        assert!((r - 0.1).abs() < 0.02, "R was {}", r);
    }
}
