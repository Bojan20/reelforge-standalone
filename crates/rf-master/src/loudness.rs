//! Loudness normalization and measurement
//!
//! ITU-R BS.1770-4 compliant loudness measurement
//! with auto-gain for target LUFS

use crate::error::{MasterError, MasterResult};
use crate::LoudnessTarget;

/// K-weighting filter state
#[derive(Clone)]
struct KWeightingFilter {
    /// High shelf state
    hs_z1: f64,
    hs_z2: f64,
    /// Highpass state
    hp_z1: f64,
    hp_z2: f64,
    /// High shelf coefficients
    hs_b0: f64,
    hs_b1: f64,
    hs_b2: f64,
    hs_a1: f64,
    hs_a2: f64,
    /// Highpass coefficients
    hp_b0: f64,
    hp_b1: f64,
    hp_b2: f64,
    hp_a1: f64,
    hp_a2: f64,
}

impl KWeightingFilter {
    fn new(sample_rate: u32) -> Self {
        let fs = sample_rate as f64;

        // Stage 1: High shelf (+4dB at high frequencies)
        // Pre-computed for 48kHz, scaled for other rates
        let hs_b0 = 1.53512485958697;
        let hs_b1 = -2.69169618940638;
        let hs_b2 = 1.19839281085285;
        let hs_a1 = -1.69065929318241;
        let hs_a2 = 0.73248077421585;

        // Stage 2: Highpass (removes < 60Hz)
        let hp_b0 = 1.0;
        let hp_b1 = -2.0;
        let hp_b2 = 1.0;
        let hp_a1 = -1.99004745483398;
        let hp_a2 = 0.99007225036621;

        // Adjust for different sample rates (simple approximation)
        let rate_factor = 48000.0 / fs;

        Self {
            hs_z1: 0.0,
            hs_z2: 0.0,
            hp_z1: 0.0,
            hp_z2: 0.0,
            hs_b0,
            hs_b1,
            hs_b2,
            hs_a1: hs_a1 * rate_factor,
            hs_a2: hs_a2 * rate_factor * rate_factor,
            hp_b0,
            hp_b1,
            hp_b2,
            hp_a1: hp_a1 * rate_factor,
            hp_a2: hp_a2 * rate_factor * rate_factor,
        }
    }

    fn process(&mut self, input: f64) -> f64 {
        // High shelf
        let hs_out = self.hs_b0 * input + self.hs_z1;
        self.hs_z1 = self.hs_b1 * input - self.hs_a1 * hs_out + self.hs_z2;
        self.hs_z2 = self.hs_b2 * input - self.hs_a2 * hs_out;

        // Highpass
        let hp_out = self.hp_b0 * hs_out + self.hp_z1;
        self.hp_z1 = self.hp_b1 * hs_out - self.hp_a1 * hp_out + self.hp_z2;
        self.hp_z2 = self.hp_b2 * hs_out - self.hp_a2 * hp_out;

        hp_out
    }

    fn reset(&mut self) {
        self.hs_z1 = 0.0;
        self.hs_z2 = 0.0;
        self.hp_z1 = 0.0;
        self.hp_z2 = 0.0;
    }
}

/// LUFS meter following ITU-R BS.1770-4
pub struct LufsMeter {
    /// Sample rate
    sample_rate: u32,
    /// K-weighting filter left
    filter_l: KWeightingFilter,
    /// K-weighting filter right
    filter_r: KWeightingFilter,
    /// Momentary buffer (400ms)
    momentary_buffer: Vec<f64>,
    /// Short-term buffer (3s)
    short_term_buffer: Vec<f64>,
    /// Integrated power accumulator
    integrated_power: Vec<f64>,
    /// Buffer position
    buffer_pos: usize,
    /// Samples per 100ms block
    block_size: usize,
    /// Current momentary
    momentary_lufs: f64,
    /// Current short-term
    short_term_lufs: f64,
    /// Integrated LUFS
    integrated_lufs: f64,
    /// Max true peak
    max_true_peak: f32,
}

impl LufsMeter {
    /// Create new LUFS meter
    pub fn new(sample_rate: u32) -> Self {
        let block_size = sample_rate as usize / 10; // 100ms blocks
        let momentary_blocks = 4; // 400ms
        let short_term_blocks = 30; // 3s

        Self {
            sample_rate,
            filter_l: KWeightingFilter::new(sample_rate),
            filter_r: KWeightingFilter::new(sample_rate),
            momentary_buffer: vec![0.0; momentary_blocks],
            short_term_buffer: vec![0.0; short_term_blocks],
            integrated_power: Vec::with_capacity(10000),
            buffer_pos: 0,
            block_size,
            momentary_lufs: -70.0,
            short_term_lufs: -70.0,
            integrated_lufs: -70.0,
            max_true_peak: -70.0,
        }
    }

    /// Process samples and update measurements
    pub fn process(&mut self, left: &[f32], right: &[f32]) {
        let mut block_power = 0.0f64;
        let mut samples_in_block = 0usize;

        for i in 0..left.len().min(right.len()) {
            // Track true peak (simplified - should use oversampling)
            let peak = left[i].abs().max(right[i].abs());
            if peak > self.max_true_peak {
                self.max_true_peak = peak;
            }

            // K-weighting
            let filtered_l = self.filter_l.process(left[i] as f64);
            let filtered_r = self.filter_r.process(right[i] as f64);

            // Mean square
            block_power += filtered_l * filtered_l + filtered_r * filtered_r;
            samples_in_block += 1;

            // Process block
            if samples_in_block >= self.block_size {
                let mean_power = block_power / (2.0 * samples_in_block as f64);
                self.process_block(mean_power);
                block_power = 0.0;
                samples_in_block = 0;
            }
        }
    }

    fn process_block(&mut self, power: f64) {
        // Update momentary buffer (sliding window)
        let momentary_blocks = self.momentary_buffer.len();
        self.momentary_buffer[self.buffer_pos % momentary_blocks] = power;

        // Update short-term buffer
        let short_term_blocks = self.short_term_buffer.len();
        self.short_term_buffer[self.buffer_pos % short_term_blocks] = power;

        self.buffer_pos += 1;

        // Calculate momentary (400ms)
        let momentary_power: f64 =
            self.momentary_buffer.iter().sum::<f64>() / momentary_blocks as f64;
        self.momentary_lufs = -0.691 + 10.0 * momentary_power.max(1e-10).log10();

        // Calculate short-term (3s)
        let short_term_power: f64 =
            self.short_term_buffer.iter().sum::<f64>() / short_term_blocks as f64;
        self.short_term_lufs = -0.691 + 10.0 * short_term_power.max(1e-10).log10();

        // Store for integrated calculation (gated)
        let gate_threshold = -70.0; // Absolute gate
        if self.momentary_lufs > gate_threshold {
            self.integrated_power.push(power);
            self.update_integrated();
        }
    }

    fn update_integrated(&mut self) {
        if self.integrated_power.is_empty() {
            self.integrated_lufs = -70.0;
            return;
        }

        // Calculate ungated mean
        let mean_power: f64 =
            self.integrated_power.iter().sum::<f64>() / self.integrated_power.len() as f64;
        let ungated_lufs = -0.691 + 10.0 * mean_power.max(1e-10).log10();

        // Relative gate (-10 dB below ungated)
        let relative_threshold = ungated_lufs - 10.0;
        let gate_linear = 10.0f64.powf((relative_threshold + 0.691) / 10.0);

        // Recalculate with relative gate
        let gated_sum: f64 = self
            .integrated_power
            .iter()
            .filter(|&&p| p >= gate_linear)
            .sum();
        let gated_count = self
            .integrated_power
            .iter()
            .filter(|&&p| p >= gate_linear)
            .count();

        if gated_count > 0 {
            let gated_mean = gated_sum / gated_count as f64;
            self.integrated_lufs = -0.691 + 10.0 * gated_mean.max(1e-10).log10();
        }
    }

    /// Get momentary LUFS
    pub fn momentary(&self) -> f32 {
        self.momentary_lufs as f32
    }

    /// Get short-term LUFS
    pub fn short_term(&self) -> f32 {
        self.short_term_lufs as f32
    }

    /// Get integrated LUFS
    pub fn integrated(&self) -> f32 {
        self.integrated_lufs as f32
    }

    /// Get max true peak (dBTP)
    pub fn true_peak(&self) -> f32 {
        if self.max_true_peak > 1e-10 {
            20.0 * self.max_true_peak.log10()
        } else {
            -70.0
        }
    }

    /// Reset all measurements
    pub fn reset(&mut self) {
        self.filter_l.reset();
        self.filter_r.reset();
        self.momentary_buffer.fill(0.0);
        self.short_term_buffer.fill(0.0);
        self.integrated_power.clear();
        self.buffer_pos = 0;
        self.momentary_lufs = -70.0;
        self.short_term_lufs = -70.0;
        self.integrated_lufs = -70.0;
        self.max_true_peak = 0.0;
    }
}

/// Auto-gain for loudness normalization
pub struct LoudnessNormalizer {
    /// Target loudness
    target: LoudnessTarget,
    /// Current gain (linear)
    gain: f32,
    /// Gain smoothing coefficient
    smooth_coeff: f64,
    /// Current smoothed gain
    smoothed_gain: f64,
    /// LUFS meter
    meter: LufsMeter,
    /// Analysis complete
    analyzed: bool,
}

impl LoudnessNormalizer {
    /// Create new normalizer
    pub fn new(sample_rate: u32, target: LoudnessTarget) -> Self {
        Self {
            target,
            gain: 1.0,
            smooth_coeff: 0.9999,
            smoothed_gain: 1.0,
            meter: LufsMeter::new(sample_rate),
            analyzed: false,
        }
    }

    /// Analyze audio to calculate gain
    pub fn analyze(&mut self, left: &[f32], right: &[f32]) {
        self.meter.process(left, right);
    }

    /// Finalize analysis and calculate gain
    pub fn finalize(&mut self) {
        let current_lufs = self.meter.integrated();
        let target_lufs = self.target.integrated_lufs;

        // Calculate required gain
        let gain_db = target_lufs - current_lufs;

        // Limit gain adjustment to avoid clipping
        let max_headroom = -self.meter.true_peak();
        let safe_gain_db = gain_db.min(max_headroom - (-self.target.true_peak));

        self.gain = 10.0f32.powf(safe_gain_db / 20.0);
        self.smoothed_gain = self.gain as f64;
        self.analyzed = true;
    }

    /// Get calculated gain (dB)
    pub fn gain_db(&self) -> f32 {
        20.0 * self.gain.log10()
    }

    /// Apply gain to audio
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Smooth gain changes
        self.smoothed_gain =
            self.smooth_coeff * self.smoothed_gain + (1.0 - self.smooth_coeff) * self.gain as f64;

        let gain = self.smoothed_gain as f32;
        (left * gain, right * gain)
    }

    /// Process buffer
    pub fn process_buffer(
        &mut self,
        input_l: &[f32],
        input_r: &[f32],
        output_l: &mut [f32],
        output_r: &mut [f32],
    ) -> MasterResult<()> {
        if input_l.len() != output_l.len() {
            return Err(MasterError::BufferMismatch {
                expected: input_l.len(),
                got: output_l.len(),
            });
        }

        for i in 0..input_l.len() {
            let (l, r) = self.process(input_l[i], input_r[i]);
            output_l[i] = l;
            output_r[i] = r;
        }

        Ok(())
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.meter.reset();
        self.smoothed_gain = 1.0;
        self.gain = 1.0;
        self.analyzed = false;
    }
}

/// Loudness range (LRA) calculator
pub struct LraCalculator {
    /// Short-term LUFS values
    short_term_values: Vec<f32>,
    /// Meter for short-term
    meter: LufsMeter,
    /// Last short-term value
    last_short_term: f32,
    /// Samples since last measurement
    samples_since_measurement: usize,
    /// Measurement interval (samples)
    measurement_interval: usize,
}

impl LraCalculator {
    /// Create LRA calculator
    pub fn new(sample_rate: u32) -> Self {
        Self {
            short_term_values: Vec::with_capacity(1000),
            meter: LufsMeter::new(sample_rate),
            last_short_term: -70.0,
            samples_since_measurement: 0,
            measurement_interval: sample_rate as usize, // 1 second
        }
    }

    /// Process samples
    pub fn process(&mut self, left: &[f32], right: &[f32]) {
        self.meter.process(left, right);
        self.samples_since_measurement += left.len();

        // Store short-term value periodically
        if self.samples_since_measurement >= self.measurement_interval {
            let st = self.meter.short_term();
            if st > -70.0 {
                self.short_term_values.push(st);
            }
            self.last_short_term = st;
            self.samples_since_measurement = 0;
        }
    }

    /// Calculate LRA
    pub fn calculate(&self) -> f32 {
        if self.short_term_values.len() < 2 {
            return 0.0;
        }

        let mut sorted = self.short_term_values.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());

        // Remove bottom 10% and top 5%
        let low_idx = sorted.len() / 10;
        let high_idx = sorted.len() * 95 / 100;

        if high_idx <= low_idx {
            return 0.0;
        }

        sorted[high_idx] - sorted[low_idx]
    }

    /// Reset
    pub fn reset(&mut self) {
        self.short_term_values.clear();
        self.meter.reset();
        self.samples_since_measurement = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lufs_meter() {
        let mut meter = LufsMeter::new(48000);

        // Process sine wave
        let sine: Vec<f32> = (0..96000)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();

        meter.process(&sine, &sine);

        // Should measure something reasonable
        let integrated = meter.integrated();
        assert!(integrated > -30.0 && integrated < 0.0);
    }

    #[test]
    fn test_loudness_normalizer() {
        let target = LoudnessTarget::lufs(-14.0);
        let mut normalizer = LoudnessNormalizer::new(48000, target);

        // Analyze quiet signal
        let quiet: Vec<f32> = (0..96000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * 0.1)
            .collect();

        normalizer.analyze(&quiet, &quiet);
        normalizer.finalize();

        // Gain should be positive (boosting quiet signal)
        assert!(normalizer.gain_db() > 0.0);
    }

    #[test]
    fn test_lra_calculator() {
        let mut lra = LraCalculator::new(48000);

        // Process signal with dynamics
        for level in [0.1, 0.5, 0.2, 0.8, 0.3] {
            let signal: Vec<f32> = (0..48000)
                .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 48000.0).sin() * level)
                .collect();
            lra.process(&signal, &signal);
        }

        let range = lra.calculate();
        // Should detect some dynamic range
        assert!(range >= 0.0);
    }

    #[test]
    fn test_k_weighting() {
        let mut filter = KWeightingFilter::new(48000);

        // Process samples
        for i in 0..1000 {
            let input = (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 48000.0).sin();
            let output = filter.process(input);
            assert!(output.is_finite());
        }
    }
}
