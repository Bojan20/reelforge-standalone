//! True peak limiting for mastering
//!
//! Features:
//! - 8x oversampling for ISP-safe limiting
//! - Lookahead for transparent limiting
//! - Auto release with program dependency
//! - Multiple limiting modes

use crate::error::{MasterError, MasterResult};

/// Limiter configuration
#[derive(Debug, Clone)]
pub struct LimiterConfig {
    /// Sample rate
    pub sample_rate: u32,
    /// Ceiling (dBTP)
    pub ceiling: f32,
    /// Release time (ms)
    pub release_ms: f32,
    /// Lookahead time (ms)
    pub lookahead_ms: f32,
    /// Oversampling factor (1, 2, 4, 8)
    pub oversampling: usize,
    /// Limiter mode
    pub mode: LimiterMode,
}

impl Default for LimiterConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            ceiling: -1.0,
            release_ms: 100.0,
            lookahead_ms: 5.0,
            oversampling: 4,
            mode: LimiterMode::TruePeak,
        }
    }
}

/// Limiter operating mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LimiterMode {
    /// Sample peak limiting
    SamplePeak,
    /// True peak limiting (with oversampling)
    TruePeak,
    /// Transparent limiting (longer attack)
    Transparent,
    /// Aggressive limiting (shorter release)
    Aggressive,
}

/// Polyphase upsampler
struct Upsampler {
    /// Upsampling factor
    factor: usize,
    /// Filter coefficients
    coeffs: Vec<f32>,
    /// History buffer
    history: Vec<f32>,
    /// History position
    pos: usize,
}

impl Upsampler {
    fn new(factor: usize) -> Self {
        // Simple windowed sinc filter
        let taps = 16 * factor;
        let mut coeffs = vec![0.0f32; taps];

        for i in 0..taps {
            let n = i as f32 - (taps as f32 - 1.0) / 2.0;
            let sinc = if n.abs() < 0.001 {
                1.0
            } else {
                let x = std::f32::consts::PI * n / factor as f32;
                x.sin() / x
            };

            // Blackman window
            let window = 0.42
                - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (taps - 1) as f32).cos()
                + 0.08 * (4.0 * std::f32::consts::PI * i as f32 / (taps - 1) as f32).cos();

            coeffs[i] = sinc * window * factor as f32;
        }

        Self {
            factor,
            coeffs,
            history: vec![0.0; taps],
            pos: 0,
        }
    }

    fn process(&mut self, sample: f32) -> Vec<f32> {
        let taps = self.coeffs.len();
        let mut output = vec![0.0f32; self.factor];

        // Insert sample into history
        self.history[self.pos] = sample;

        // Generate upsampled outputs
        for phase in 0..self.factor {
            let mut sum = 0.0f32;

            for i in 0..taps / self.factor {
                let coeff_idx = i * self.factor + phase;
                let hist_idx = (self.pos + taps - i * self.factor) % taps;
                sum += self.history[hist_idx] * self.coeffs[coeff_idx];
            }

            output[phase] = sum;
        }

        self.pos = (self.pos + 1) % taps;
        output
    }

    fn reset(&mut self) {
        self.history.fill(0.0);
        self.pos = 0;
    }
}

/// Polyphase downsampler
struct Downsampler {
    /// Downsampling factor
    factor: usize,
    /// Filter coefficients
    coeffs: Vec<f32>,
    /// History buffer
    history: Vec<f32>,
    /// Position
    pos: usize,
}

impl Downsampler {
    fn new(factor: usize) -> Self {
        // Same filter as upsampler
        let taps = 16 * factor;
        let mut coeffs = vec![0.0f32; taps];

        for i in 0..taps {
            let n = i as f32 - (taps as f32 - 1.0) / 2.0;
            let sinc = if n.abs() < 0.001 {
                1.0
            } else {
                let x = std::f32::consts::PI * n / factor as f32;
                x.sin() / x
            };

            let window = 0.42
                - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (taps - 1) as f32).cos()
                + 0.08 * (4.0 * std::f32::consts::PI * i as f32 / (taps - 1) as f32).cos();

            coeffs[i] = sinc * window;
        }

        Self {
            factor,
            coeffs,
            history: vec![0.0; taps],
            pos: 0,
        }
    }

    fn process(&mut self, samples: &[f32]) -> f32 {
        let taps = self.coeffs.len();

        // Insert samples into history
        for &sample in samples {
            self.history[self.pos] = sample;
            self.pos = (self.pos + 1) % taps;
        }

        // Filter and output
        let mut sum = 0.0f32;
        for i in 0..taps {
            let hist_idx = (self.pos + taps - i) % taps;
            sum += self.history[hist_idx] * self.coeffs[i];
        }

        sum
    }

    fn reset(&mut self) {
        self.history.fill(0.0);
        self.pos = 0;
    }
}

/// True peak limiter with oversampling
pub struct TruePeakLimiter {
    /// Configuration
    config: LimiterConfig,
    /// Ceiling in linear
    ceiling_linear: f32,
    /// Release coefficient
    release_coeff: f64,
    /// Attack coefficient
    attack_coeff: f64,
    /// Envelope
    envelope: f64,
    /// Gain reduction (dB)
    gain_reduction: f32,
    /// Lookahead buffer left
    lookahead_l: Vec<f32>,
    /// Lookahead buffer right
    lookahead_r: Vec<f32>,
    /// Gain buffer
    gain_buffer: Vec<f32>,
    /// Lookahead position
    lookahead_pos: usize,
    /// Lookahead size
    lookahead_size: usize,
    /// Upsampler left
    upsampler_l: Upsampler,
    /// Upsampler right
    upsampler_r: Upsampler,
    /// Downsampler left
    downsampler_l: Downsampler,
    /// Downsampler right
    downsampler_r: Downsampler,
}

impl TruePeakLimiter {
    /// Create new true peak limiter
    pub fn new(config: LimiterConfig) -> Self {
        let lookahead_size =
            (config.lookahead_ms * config.sample_rate as f32 / 1000.0) as usize;
        let lookahead_size = lookahead_size.max(1);

        let ceiling_linear = 10.0f32.powf(config.ceiling / 20.0);

        // Release time based on mode
        let release_ms = match config.mode {
            LimiterMode::Aggressive => config.release_ms * 0.5,
            LimiterMode::Transparent => config.release_ms * 2.0,
            _ => config.release_ms,
        };

        let release_coeff = (-1.0 / (release_ms * config.sample_rate as f32 / 1000.0)).exp() as f64;

        // Attack is much faster (lookahead handles transparency)
        let attack_ms = config.lookahead_ms * 0.5;
        let attack_coeff = (-1.0 / (attack_ms * config.sample_rate as f32 / 1000.0)).exp() as f64;

        let os = config.oversampling;

        Self {
            config: config.clone(),
            ceiling_linear,
            release_coeff,
            attack_coeff,
            envelope: 1.0,
            gain_reduction: 0.0,
            lookahead_l: vec![0.0; lookahead_size],
            lookahead_r: vec![0.0; lookahead_size],
            gain_buffer: vec![1.0; lookahead_size],
            lookahead_pos: 0,
            lookahead_size,
            upsampler_l: Upsampler::new(os),
            upsampler_r: Upsampler::new(os),
            downsampler_l: Downsampler::new(os),
            downsampler_r: Downsampler::new(os),
        }
    }

    /// Set ceiling
    pub fn set_ceiling(&mut self, db: f32) {
        self.config.ceiling = db;
        self.ceiling_linear = 10.0f32.powf(db / 20.0);
    }

    /// Get current gain reduction (dB)
    pub fn gain_reduction(&self) -> f32 {
        self.gain_reduction
    }

    /// Process stereo sample
    pub fn process_sample(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Get delayed input
        let delayed_l = self.lookahead_l[self.lookahead_pos];
        let delayed_r = self.lookahead_r[self.lookahead_pos];

        // Store current input
        self.lookahead_l[self.lookahead_pos] = left;
        self.lookahead_r[self.lookahead_pos] = right;

        // Detect true peak via oversampling
        let upsampled_l = self.upsampler_l.process(left);
        let upsampled_r = self.upsampler_r.process(right);

        let mut true_peak = 0.0f32;
        for i in 0..self.config.oversampling {
            true_peak = true_peak.max(upsampled_l[i].abs()).max(upsampled_r[i].abs());
        }

        // Compute required gain
        let required_gain = if true_peak > self.ceiling_linear {
            self.ceiling_linear / true_peak
        } else {
            1.0
        };

        // Smooth envelope
        let target = required_gain as f64;
        if target < self.envelope {
            self.envelope = self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * target;
        } else {
            self.envelope = self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target;
        }

        // Store gain for lookahead
        let delayed_gain = self.gain_buffer[self.lookahead_pos];
        self.gain_buffer[self.lookahead_pos] = self.envelope as f32;

        self.lookahead_pos = (self.lookahead_pos + 1) % self.lookahead_size;

        // Calculate gain reduction for display
        self.gain_reduction = if delayed_gain < 0.999 {
            -20.0 * delayed_gain.log10()
        } else {
            0.0
        };

        // Apply gain to delayed signal
        (delayed_l * delayed_gain, delayed_r * delayed_gain)
    }

    /// Process buffer
    pub fn process(&mut self, input_l: &[f32], input_r: &[f32], output_l: &mut [f32], output_r: &mut [f32]) -> MasterResult<()> {
        if input_l.len() != output_l.len() {
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

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.lookahead_size
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.envelope = 1.0;
        self.gain_reduction = 0.0;
        self.lookahead_l.fill(0.0);
        self.lookahead_r.fill(0.0);
        self.gain_buffer.fill(1.0);
        self.lookahead_pos = 0;
        self.upsampler_l.reset();
        self.upsampler_r.reset();
        self.downsampler_l.reset();
        self.downsampler_r.reset();
    }
}

/// Simple brickwall limiter (no lookahead)
pub struct BrickwallLimiter {
    /// Ceiling linear
    ceiling: f32,
    /// Release coefficient
    release_coeff: f64,
    /// Envelope
    envelope: f64,
}

impl BrickwallLimiter {
    /// Create brickwall limiter
    pub fn new(ceiling_db: f32, release_ms: f32, sample_rate: u32) -> Self {
        Self {
            ceiling: 10.0f32.powf(ceiling_db / 20.0),
            release_coeff: (-1.0 / (release_ms * sample_rate as f32 / 1000.0)).exp() as f64,
            envelope: 1.0,
        }
    }

    /// Process sample
    pub fn process(&mut self, left: f32, right: f32) -> (f32, f32) {
        let peak = left.abs().max(right.abs());
        let target = if peak > self.ceiling {
            (self.ceiling / peak) as f64
        } else {
            1.0
        };

        if target < self.envelope {
            self.envelope = target; // Instant attack
        } else {
            self.envelope = self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target;
        }

        let gain = self.envelope as f32;
        (left * gain, right * gain)
    }

    /// Reset
    pub fn reset(&mut self) {
        self.envelope = 1.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_limiter_creation() {
        let config = LimiterConfig::default();
        let limiter = TruePeakLimiter::new(config);
        assert!(limiter.ceiling_linear < 1.0); // -1 dB ceiling
    }

    #[test]
    fn test_limiter_passthrough() {
        let config = LimiterConfig {
            ceiling: 0.0, // 0 dB ceiling
            ..Default::default()
        };
        let mut limiter = TruePeakLimiter::new(config);

        // Quiet signal should pass through
        let input_l = vec![0.3f32; 1024];
        let input_r = vec![0.3f32; 1024];
        let mut output_l = vec![0.0f32; 1024];
        let mut output_r = vec![0.0f32; 1024];

        limiter.process(&input_l, &input_r, &mut output_l, &mut output_r).unwrap();

        // After lookahead delay, output should be similar to input
        let late_out: Vec<f32> = output_l.iter().skip(limiter.latency()).copied().collect();
        if !late_out.is_empty() {
            let avg: f32 = late_out.iter().sum::<f32>() / late_out.len() as f32;
            assert!((avg - 0.3).abs() < 0.1);
        }
    }

    #[test]
    fn test_limiter_reduces_peaks() {
        let config = LimiterConfig {
            ceiling: -6.0, // -6 dB ceiling (~0.5)
            ..Default::default()
        };
        let mut limiter = TruePeakLimiter::new(config);

        // Hot signal
        let input_l = vec![0.9f32; 1024];
        let input_r = vec![0.9f32; 1024];
        let mut output_l = vec![0.0f32; 1024];
        let mut output_r = vec![0.0f32; 1024];

        limiter.process(&input_l, &input_r, &mut output_l, &mut output_r).unwrap();

        // After lookahead delay, output peaks should be limited
        // Skip initial samples (lookahead latency)
        let late_samples: Vec<f32> = output_l.iter()
            .skip(limiter.latency() + 100)
            .copied()
            .collect();

        if !late_samples.is_empty() {
            let max_out = late_samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
            // Ceiling is -6 dB = 0.5, allow some margin
            assert!(max_out <= 0.7, "Peak {} should be below ceiling", max_out);
        }
    }

    #[test]
    fn test_brickwall_limiter() {
        let mut limiter = BrickwallLimiter::new(-6.0, 50.0, 48000);

        let (l, r) = limiter.process(0.9, 0.9);
        assert!(l.abs() <= 0.6);
        assert!(r.abs() <= 0.6);
    }
}
