//! Stereo enhancement for mastering
//!
//! Features:
//! - Width control
//! - M/S processing
//! - Low frequency mono
//! - Stereo imaging

use crate::error::{MasterError, MasterResult};

/// Stereo enhancer configuration
#[derive(Debug, Clone)]
pub struct StereoConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Width (0.0 = mono, 1.0 = normal, 2.0 = double width)
    pub width: f32,
    /// Low frequency mono cutoff (Hz)
    pub low_mono_freq: f32,
    /// Low mono amount (0-1)
    pub low_mono_amount: f32,
    /// Mid gain (dB)
    pub mid_gain_db: f32,
    /// Side gain (dB)
    pub side_gain_db: f32,
}

impl Default for StereoConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            width: 1.0,
            low_mono_freq: 120.0,
            low_mono_amount: 1.0,
            mid_gain_db: 0.0,
            side_gain_db: 0.0,
        }
    }
}

/// Mid-Side encoder/decoder
pub struct MidSideProcessor {
    /// Mid gain (linear)
    mid_gain: f32,
    /// Side gain (linear)
    side_gain: f32,
}

impl MidSideProcessor {
    /// Create new M/S processor
    pub fn new() -> Self {
        Self {
            mid_gain: 1.0,
            side_gain: 1.0,
        }
    }

    /// Set mid gain
    pub fn set_mid_gain(&mut self, db: f32) {
        self.mid_gain = 10.0f32.powf(db / 20.0);
    }

    /// Set side gain
    pub fn set_side_gain(&mut self, db: f32) {
        self.side_gain = 10.0f32.powf(db / 20.0);
    }

    /// Encode L/R to M/S
    pub fn encode(&self, left: f32, right: f32) -> (f32, f32) {
        let mid = (left + right) * 0.5 * self.mid_gain;
        let side = (left - right) * 0.5 * self.side_gain;
        (mid, side)
    }

    /// Decode M/S to L/R
    pub fn decode(&self, mid: f32, side: f32) -> (f32, f32) {
        let left = mid + side;
        let right = mid - side;
        (left, right)
    }

    /// Process L/R through M/S domain with gains
    pub fn process(&self, left: f32, right: f32) -> (f32, f32) {
        let (mid, side) = self.encode(left, right);
        self.decode(mid, side)
    }
}

impl Default for MidSideProcessor {
    fn default() -> Self {
        Self::new()
    }
}

/// Stereo width control
pub struct StereoWidth {
    /// Width factor
    width: f32,
    /// M/S processor
    ms: MidSideProcessor,
}

impl StereoWidth {
    /// Create width processor
    pub fn new() -> Self {
        Self {
            width: 1.0,
            ms: MidSideProcessor::new(),
        }
    }

    /// Set width (0 = mono, 1 = normal, 2 = double)
    pub fn set_width(&mut self, width: f32) {
        self.width = width.max(0.0);
    }

    /// Process stereo sample
    pub fn process(&self, left: f32, right: f32) -> (f32, f32) {
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;

        // Scale side by width
        let scaled_side = side * self.width;

        // Decode back to L/R
        let out_l = mid + scaled_side;
        let out_r = mid - scaled_side;

        (out_l, out_r)
    }
}

impl Default for StereoWidth {
    fn default() -> Self {
        Self::new()
    }
}

/// Low frequency mono processor
pub struct LowMono {
    /// Crossover frequency
    crossover_freq: f32,
    /// Sample rate
    sample_rate: u32,
    /// Filter coefficient
    coeff: f64,
    /// Low frequency state L
    lp_l: f64,
    /// Low frequency state R
    lp_r: f64,
    /// Mono amount (0-1)
    mono_amount: f32,
}

impl LowMono {
    /// Create low mono processor
    pub fn new(sample_rate: u32) -> Self {
        let crossover_freq = 120.0;
        let omega = 2.0 * std::f64::consts::PI * crossover_freq as f64 / sample_rate as f64;
        let coeff = omega / (omega + 1.0);

        Self {
            crossover_freq,
            sample_rate,
            coeff,
            lp_l: 0.0,
            lp_r: 0.0,
            mono_amount: 1.0,
        }
    }

    /// Set crossover frequency
    pub fn set_crossover(&mut self, freq: f32) {
        self.crossover_freq = freq;
        let omega = 2.0 * std::f64::consts::PI * freq as f64 / self.sample_rate as f64;
        self.coeff = omega / (omega + 1.0);
    }

    /// Set mono amount
    pub fn set_amount(&mut self, amount: f32) {
        self.mono_amount = amount.clamp(0.0, 1.0);
    }

    /// Process stereo sample
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Extract low frequencies
        self.lp_l += self.coeff * (left as f64 - self.lp_l);
        self.lp_r += self.coeff * (right as f64 - self.lp_r);

        // High frequencies (original minus low)
        let hp_l = left as f64 - self.lp_l;
        let hp_r = right as f64 - self.lp_r;

        // Mono low frequencies
        let low_mono = (self.lp_l + self.lp_r) * 0.5;

        // Blend mono and stereo low
        let low_l =
            self.lp_l * (1.0 - self.mono_amount as f64) + low_mono * self.mono_amount as f64;
        let low_r =
            self.lp_r * (1.0 - self.mono_amount as f64) + low_mono * self.mono_amount as f64;

        // Combine
        ((low_l + hp_l) as f32, (low_r + hp_r) as f32)
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.lp_l = 0.0;
        self.lp_r = 0.0;
    }
}

/// Full stereo enhancer
pub struct StereoEnhancer {
    /// Configuration
    config: StereoConfig,
    /// Width processor
    width: StereoWidth,
    /// M/S processor
    ms: MidSideProcessor,
    /// Low mono processor
    low_mono: LowMono,
}

impl StereoEnhancer {
    /// Create stereo enhancer
    pub fn new(config: StereoConfig) -> Self {
        let mut width = StereoWidth::new();
        width.set_width(config.width);

        let mut ms = MidSideProcessor::new();
        ms.set_mid_gain(config.mid_gain_db);
        ms.set_side_gain(config.side_gain_db);

        let mut low_mono = LowMono::new(config.sample_rate);
        low_mono.set_crossover(config.low_mono_freq);
        low_mono.set_amount(config.low_mono_amount);

        Self {
            config,
            width,
            ms,
            low_mono,
        }
    }

    /// Set width
    pub fn set_width(&mut self, width: f32) {
        self.config.width = width;
        self.width.set_width(width);
    }

    /// Set low mono frequency
    pub fn set_low_mono_freq(&mut self, freq: f32) {
        self.config.low_mono_freq = freq;
        self.low_mono.set_crossover(freq);
    }

    /// Set low mono amount
    pub fn set_low_mono_amount(&mut self, amount: f32) {
        self.config.low_mono_amount = amount;
        self.low_mono.set_amount(amount);
    }

    /// Set M/S balance
    pub fn set_ms_balance(&mut self, mid_db: f32, side_db: f32) {
        self.config.mid_gain_db = mid_db;
        self.config.side_gain_db = side_db;
        self.ms.set_mid_gain(mid_db);
        self.ms.set_side_gain(side_db);
    }

    /// Process stereo sample
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Apply low mono first
        let (l, r) = self.low_mono.process(left, right);

        // Apply width
        let (l, r) = self.width.process(l, r);

        // Apply M/S processing
        self.ms.process(l, r)
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
        self.low_mono.reset();
    }
}

/// Stereo correlation meter
pub struct CorrelationMeter {
    /// Averaging buffer size
    buffer_size: usize,
    /// Sum of L*R
    sum_lr: f64,
    /// Sum of L^2
    sum_l2: f64,
    /// Sum of R^2
    sum_r2: f64,
    /// Sample count
    count: usize,
}

impl CorrelationMeter {
    /// Create correlation meter
    pub fn new(averaging_samples: usize) -> Self {
        Self {
            buffer_size: averaging_samples,
            sum_lr: 0.0,
            sum_l2: 0.0,
            sum_r2: 0.0,
            count: 0,
        }
    }

    /// Process sample
    pub fn process(&mut self, left: f32, right: f32) {
        let l = left as f64;
        let r = right as f64;

        self.sum_lr += l * r;
        self.sum_l2 += l * l;
        self.sum_r2 += r * r;
        self.count += 1;

        // Simple averaging (could use ring buffer for true sliding window)
        if self.count > self.buffer_size {
            let scale = 0.999;
            self.sum_lr *= scale;
            self.sum_l2 *= scale;
            self.sum_r2 *= scale;
        }
    }

    /// Get correlation (-1 to +1)
    pub fn correlation(&self) -> f32 {
        let denom = (self.sum_l2 * self.sum_r2).sqrt();
        if denom > 1e-10 {
            (self.sum_lr / denom) as f32
        } else {
            0.0
        }
    }

    /// Reset
    pub fn reset(&mut self) {
        self.sum_lr = 0.0;
        self.sum_l2 = 0.0;
        self.sum_r2 = 0.0;
        self.count = 0;
    }
}

/// Stereo balance meter
pub struct BalanceMeter {
    /// Left energy
    energy_l: f64,
    /// Right energy
    energy_r: f64,
    /// Smoothing
    smoothing: f64,
}

impl BalanceMeter {
    /// Create balance meter
    pub fn new(sample_rate: u32) -> Self {
        // ~300ms smoothing
        let smoothing = (-1.0 / (0.3 * sample_rate as f64)).exp();

        Self {
            energy_l: 0.0,
            energy_r: 0.0,
            smoothing,
        }
    }

    /// Process sample
    pub fn process(&mut self, left: f32, right: f32) {
        let l2 = (left * left) as f64;
        let r2 = (right * right) as f64;

        self.energy_l = self.smoothing * self.energy_l + (1.0 - self.smoothing) * l2;
        self.energy_r = self.smoothing * self.energy_r + (1.0 - self.smoothing) * r2;
    }

    /// Get balance (-1 = left, 0 = center, +1 = right)
    pub fn balance(&self) -> f32 {
        let total = self.energy_l + self.energy_r;
        if total > 1e-10 {
            ((self.energy_r - self.energy_l) / total) as f32
        } else {
            0.0
        }
    }

    /// Get balance in dB (negative = left, positive = right)
    pub fn balance_db(&self) -> f32 {
        if self.energy_l > 1e-10 && self.energy_r > 1e-10 {
            10.0 * (self.energy_r / self.energy_l).log10() as f32
        } else {
            0.0
        }
    }

    /// Reset
    pub fn reset(&mut self) {
        self.energy_l = 0.0;
        self.energy_r = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ms_encode_decode() {
        let ms = MidSideProcessor::new();

        // Encode and decode should be identity
        let (l, r) = (0.7, 0.3);
        let (mid, side) = ms.encode(l, r);
        let (l2, r2) = ms.decode(mid, side);

        assert!((l - l2).abs() < 0.001);
        assert!((r - r2).abs() < 0.001);
    }

    #[test]
    fn test_stereo_width() {
        let mut width = StereoWidth::new();

        // Width 0 should produce mono
        width.set_width(0.0);
        let (l, r) = width.process(1.0, 0.0);
        assert!((l - r).abs() < 0.001, "Mono: L={}, R={}", l, r);

        // Width 1 should preserve original
        // Input (1, 0): mid = 0.5, side = 0.5
        // With width 1: scaled_side = 0.5
        // Output: L = mid + side = 1.0, R = mid - side = 0.0
        width.set_width(1.0);
        let (l, r) = width.process(1.0, 0.0);
        assert!((l - 1.0).abs() < 0.001, "Unity L={}", l);
        assert!((r - 0.0).abs() < 0.001, "Unity R={}", r);
    }

    #[test]
    fn test_low_mono() {
        let mut low_mono = LowMono::new(48000);
        low_mono.set_crossover(100.0);
        low_mono.set_amount(1.0);

        // Process some samples
        for i in 0..1000 {
            let t = i as f32 / 48000.0;
            // Low frequency content
            let low = (2.0 * std::f32::consts::PI * 60.0 * t).sin();
            // Different in L/R
            let (l, r) = low_mono.process(low, -low);
            assert!(l.is_finite());
            assert!(r.is_finite());
        }
    }

    #[test]
    fn test_stereo_enhancer() {
        let config = StereoConfig::default();
        let mut enhancer = StereoEnhancer::new(config);

        let input_l = vec![0.5f32; 1024];
        let input_r = vec![0.3f32; 1024];
        let mut output_l = vec![0.0f32; 1024];
        let mut output_r = vec![0.0f32; 1024];

        enhancer
            .process_buffer(&input_l, &input_r, &mut output_l, &mut output_r)
            .unwrap();

        assert!(output_l.iter().all(|s| s.is_finite()));
        assert!(output_r.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn test_correlation_meter() {
        let mut meter = CorrelationMeter::new(1000);

        // Correlated signal
        for _ in 0..1000 {
            meter.process(0.5, 0.5);
        }
        assert!(meter.correlation() > 0.99);

        meter.reset();

        // Anti-correlated signal
        for _ in 0..1000 {
            meter.process(0.5, -0.5);
        }
        assert!(meter.correlation() < -0.99);
    }

    #[test]
    fn test_balance_meter() {
        let mut meter = BalanceMeter::new(48000);

        // Left heavy
        for _ in 0..10000 {
            meter.process(0.8, 0.2);
        }
        assert!(meter.balance() < 0.0);

        meter.reset();

        // Right heavy
        for _ in 0..10000 {
            meter.process(0.2, 0.8);
        }
        assert!(meter.balance() > 0.0);
    }
}
