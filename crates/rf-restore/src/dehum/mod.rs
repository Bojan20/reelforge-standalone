//! Hum removal - eliminate mains frequency hum and harmonics
//!
//! Features:
//! - Auto-detect 50/60 Hz
//! - Remove up to 16 harmonics
//! - Adaptive notch filters
//! - Phase-locked tracking

use crate::error::{RestoreError, RestoreResult};
use crate::{RestoreConfig, Restorer};

/// Dehum configuration
#[derive(Debug, Clone)]
pub struct DehumConfig {
    /// Base configuration
    pub base: RestoreConfig,
    /// Fundamental frequency (0 = auto-detect)
    pub frequency: f32,
    /// Number of harmonics to remove
    pub harmonics: usize,
    /// Notch Q factor (higher = narrower)
    pub q: f32,
    /// Adaptive tracking
    pub adaptive: bool,
    /// Reduction amount (dB)
    pub reduction_db: f32,
}

impl Default for DehumConfig {
    fn default() -> Self {
        Self {
            base: RestoreConfig::default(),
            frequency: 0.0, // Auto-detect
            harmonics: 8,
            q: 10.0,
            adaptive: true,
            reduction_db: 60.0,
        }
    }
}

/// Biquad notch filter
#[derive(Clone)]
struct NotchFilter {
    /// Coefficients
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    /// State
    z1: f64,
    z2: f64,
    /// Center frequency
    freq: f32,
    /// Q factor
    q: f32,
}

impl NotchFilter {
    fn new(freq: f32, q: f32, sample_rate: u32) -> Self {
        let mut filter = Self {
            b0: 1.0,
            b1: 0.0,
            b2: 1.0,
            a1: 0.0,
            a2: 0.0,
            z1: 0.0,
            z2: 0.0,
            freq,
            q,
        };
        filter.update_coeffs(freq, q, sample_rate);
        filter
    }

    fn update_coeffs(&mut self, freq: f32, q: f32, sample_rate: u32) {
        let omega = 2.0 * std::f64::consts::PI * freq as f64 / sample_rate as f64;
        let alpha = omega.sin() / (2.0 * q as f64);

        let b0 = 1.0;
        let b1 = -2.0 * omega.cos();
        let b2 = 1.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * omega.cos();
        let a2 = 1.0 - alpha;

        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
        self.freq = freq;
        self.q = q;
    }

    fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }

    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

/// Hum removal processor
pub struct Dehum {
    /// Configuration
    config: DehumConfig,
    /// Sample rate
    sample_rate: u32,
    /// Notch filters (one per harmonic)
    notches: Vec<NotchFilter>,
    /// Detected fundamental
    detected_freq: f32,
    /// Detection buffer
    detection_buffer: Vec<f32>,
    /// Detection position
    detection_pos: usize,
}

impl Dehum {
    /// Create new dehum processor
    pub fn new(config: DehumConfig, sample_rate: u32) -> Self {
        let freq = if config.frequency > 0.0 {
            config.frequency
        } else {
            50.0 // Default, will be auto-detected
        };

        let notches = Self::create_notches(freq, config.harmonics, config.q, sample_rate);

        Self {
            config: config.clone(),
            sample_rate,
            notches,
            detected_freq: freq,
            detection_buffer: vec![0.0; sample_rate as usize], // 1 second buffer
            detection_pos: 0,
        }
    }

    /// Create notch filter bank
    fn create_notches(fundamental: f32, harmonics: usize, q: f32, sample_rate: u32) -> Vec<NotchFilter> {
        (1..=harmonics)
            .map(|h| {
                let freq = fundamental * h as f32;
                // Reduce Q for higher harmonics (wider notches)
                let harmonic_q = q * (1.0 / (h as f32).sqrt());
                NotchFilter::new(freq, harmonic_q, sample_rate)
            })
            .collect()
    }

    /// Auto-detect hum frequency (50 or 60 Hz)
    fn detect_frequency(&mut self, audio: &[f32]) -> f32 {
        // Add to detection buffer
        for &sample in audio {
            self.detection_buffer[self.detection_pos] = sample;
            self.detection_pos = (self.detection_pos + 1) % self.detection_buffer.len();
        }

        // Simple energy comparison at 50 and 60 Hz
        let samples = &self.detection_buffer;
        let energy_50 = self.measure_frequency_energy(samples, 50.0);
        let energy_60 = self.measure_frequency_energy(samples, 60.0);

        if energy_50 > energy_60 * 1.2 {
            50.0
        } else if energy_60 > energy_50 * 1.2 {
            60.0
        } else {
            self.detected_freq // Keep current
        }
    }

    /// Measure energy at specific frequency using correlation
    fn measure_frequency_energy(&self, samples: &[f32], freq: f32) -> f32 {
        let period_samples = self.sample_rate as f32 / freq;
        let mut sin_sum = 0.0f32;
        let mut cos_sum = 0.0f32;

        for (i, &sample) in samples.iter().enumerate() {
            let phase = 2.0 * std::f32::consts::PI * i as f32 / period_samples;
            sin_sum += sample * phase.sin();
            cos_sum += sample * phase.cos();
        }

        (sin_sum * sin_sum + cos_sum * cos_sum).sqrt() / samples.len() as f32
    }

    /// Update filter frequencies
    fn update_filters(&mut self, new_freq: f32) {
        if (new_freq - self.detected_freq).abs() > 0.5 {
            self.detected_freq = new_freq;
            self.notches = Self::create_notches(
                new_freq,
                self.config.harmonics,
                self.config.q,
                self.sample_rate,
            );
        }
    }

    /// Get detected hum frequency
    pub fn detected_frequency(&self) -> f32 {
        self.detected_freq
    }
}

impl Restorer for Dehum {
    fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()> {
        if input.len() != output.len() {
            return Err(RestoreError::BufferMismatch {
                expected: input.len(),
                got: output.len(),
            });
        }

        // Auto-detect if enabled
        if self.config.frequency == 0.0 && self.config.adaptive {
            let detected = self.detect_frequency(input);
            self.update_filters(detected);
        }

        // Apply notch filters in cascade
        for (i, &sample) in input.iter().enumerate() {
            let mut processed = sample as f64;

            for notch in &mut self.notches {
                processed = notch.process(processed);
            }

            output[i] = processed as f32;
        }

        Ok(())
    }

    fn reset(&mut self) {
        for notch in &mut self.notches {
            notch.reset();
        }
        self.detection_buffer.fill(0.0);
        self.detection_pos = 0;
    }

    fn latency_samples(&self) -> usize {
        0 // IIR filters have no inherent latency (group delay only)
    }

    fn name(&self) -> &str {
        "Dehum"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dehum_creation() {
        let config = DehumConfig::default();
        let dehum = Dehum::new(config, 48000);
        assert_eq!(dehum.name(), "Dehum");
    }

    #[test]
    fn test_notch_filter() {
        let mut notch = NotchFilter::new(50.0, 10.0, 48000);

        // Process impulse
        let output = notch.process(1.0);
        assert!(output.is_finite());

        // Process zeros
        for _ in 0..100 {
            let out = notch.process(0.0);
            assert!(out.abs() < 1.0);
        }
    }

    #[test]
    fn test_dehum_process() {
        let config = DehumConfig {
            frequency: 50.0,
            harmonics: 4,
            ..Default::default()
        };
        let mut dehum = Dehum::new(config, 48000);

        // Create signal with 50Hz hum
        let hum: Vec<f32> = (0..4800).map(|i| {
            let t = i as f32 / 48000.0;
            // 50Hz + harmonics
            (2.0 * std::f32::consts::PI * 50.0 * t).sin() * 0.5
                + (2.0 * std::f32::consts::PI * 100.0 * t).sin() * 0.3
                + (2.0 * std::f32::consts::PI * 150.0 * t).sin() * 0.2
        }).collect();

        let mut output = vec![0.0f32; hum.len()];
        dehum.process(&hum, &mut output).unwrap();

        // Output should have lower energy (hum removed)
        let input_energy: f32 = hum.iter().map(|s| s * s).sum();
        let output_energy: f32 = output.iter().map(|s| s * s).sum();

        assert!(output_energy < input_energy * 0.5, "Hum should be reduced");
    }
}
