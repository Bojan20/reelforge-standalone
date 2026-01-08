//! DSD Decimation Filters
//!
//! High-quality multi-stage decimation for DSD → PCM conversion.
//! Supports all DSD rates (64/128/256/512) to any PCM rate.

use rf_core::Sample;
use std::f64::consts::PI;

/// Decimation quality level
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecimationQuality {
    /// Fast decimation, lower quality
    Fast,
    /// Standard quality (good for preview)
    Standard,
    /// High quality (recommended for export)
    High,
    /// Ultimate quality (audiophile)
    Ultimate,
}

impl Default for DecimationQuality {
    fn default() -> Self {
        Self::High
    }
}

impl DecimationQuality {
    /// Get filter order for this quality
    fn filter_order(self) -> usize {
        match self {
            DecimationQuality::Fast => 32,
            DecimationQuality::Standard => 64,
            DecimationQuality::High => 128,
            DecimationQuality::Ultimate => 256,
        }
    }

    /// Get stopband attenuation in dB
    fn stopband_attenuation(self) -> f64 {
        match self {
            DecimationQuality::Fast => 60.0,
            DecimationQuality::Standard => 80.0,
            DecimationQuality::High => 120.0,
            DecimationQuality::Ultimate => 140.0,
        }
    }
}

/// Multi-stage DSD decimator
pub struct DsdDecimator {
    /// Decimation stages
    stages: Vec<DecimationStage>,
    /// Total decimation factor
    total_factor: u32,
    /// Output sample rate
    output_rate: f64,
}

impl DsdDecimator {
    /// Create new decimator
    pub fn new(dsd_rate: f64, output_rate: f64, quality: DecimationQuality) -> Self {
        let total_factor = (dsd_rate / output_rate).round() as u32;

        // Determine optimal stage factors
        let factors = Self::optimal_factors(total_factor);

        // Create stages
        let mut current_rate = dsd_rate;
        let mut stages = Vec::new();

        for factor in factors {
            let stage = DecimationStage::new(factor, current_rate, quality);
            stages.push(stage);
            current_rate /= factor as f64;
        }

        Self {
            stages,
            total_factor,
            output_rate,
        }
    }

    /// Calculate optimal decimation factors
    fn optimal_factors(total: u32) -> Vec<u32> {
        let mut factors = Vec::new();
        let mut remaining = total;

        // Prefer factors of 8, then 4, then 2
        while remaining > 1 {
            if remaining % 8 == 0 && remaining >= 8 {
                factors.push(8);
                remaining /= 8;
            } else if remaining % 4 == 0 && remaining >= 4 {
                factors.push(4);
                remaining /= 4;
            } else if remaining % 2 == 0 {
                factors.push(2);
                remaining /= 2;
            } else {
                // Handle odd factors
                factors.push(remaining);
                break;
            }
        }

        factors
    }

    /// Process DSD samples (as +1/-1 values)
    pub fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        let mut current = input.to_vec();

        for stage in &mut self.stages {
            current = stage.process(&current);
        }

        current
    }

    /// Process DSD bits directly
    pub fn process_bits(&mut self, bits: &[u8]) -> Vec<Sample> {
        // Convert bits to +1/-1
        let samples: Vec<Sample> = bits.iter()
            .map(|&b| if b == 1 { 1.0 } else { -1.0 })
            .collect();

        self.process(&samples)
    }

    /// Get total decimation factor
    pub fn factor(&self) -> u32 {
        self.total_factor
    }

    /// Get output sample rate
    pub fn output_rate(&self) -> f64 {
        self.output_rate
    }

    /// Reset all stages
    pub fn reset(&mut self) {
        for stage in &mut self.stages {
            stage.reset();
        }
    }
}

/// Single decimation stage
struct DecimationStage {
    /// Decimation factor
    factor: u32,
    /// FIR filter coefficients
    coefficients: Vec<f64>,
    /// Filter delay line
    delay_line: Vec<Sample>,
    /// Current position in delay line
    position: usize,
    /// Sample counter for decimation
    sample_counter: u32,
}

impl DecimationStage {
    /// Create new decimation stage
    fn new(factor: u32, input_rate: f64, quality: DecimationQuality) -> Self {
        let order = quality.filter_order();
        let attenuation = quality.stopband_attenuation();

        // Calculate cutoff frequency
        // Cutoff at Nyquist of output rate with some margin
        let output_rate = input_rate / factor as f64;
        let cutoff = 0.45 * output_rate / input_rate; // Slightly below Nyquist

        // Design lowpass filter
        let coefficients = Self::design_lowpass(order, cutoff, attenuation);

        Self {
            factor,
            coefficients: coefficients.clone(),
            delay_line: vec![0.0; coefficients.len()],
            position: 0,
            sample_counter: 0,
        }
    }

    /// Design lowpass FIR filter using Kaiser window
    fn design_lowpass(order: usize, cutoff: f64, attenuation: f64) -> Vec<f64> {
        let mut coeffs = vec![0.0; order];

        // Calculate Kaiser beta from attenuation
        let beta = if attenuation > 50.0 {
            0.1102 * (attenuation - 8.7)
        } else if attenuation >= 21.0 {
            0.5842 * (attenuation - 21.0).powf(0.4) + 0.07886 * (attenuation - 21.0)
        } else {
            0.0
        };

        // Generate sinc function windowed by Kaiser
        let m = order as f64 - 1.0;
        let i0_beta = Self::bessel_i0(beta);

        for i in 0..order {
            let n = i as f64 - m / 2.0;

            // Sinc function
            let sinc = if n.abs() < 1e-10 {
                2.0 * cutoff
            } else {
                (2.0 * PI * cutoff * n).sin() / (PI * n)
            };

            // Kaiser window
            let x = 2.0 * i as f64 / m - 1.0;
            let kaiser = Self::bessel_i0(beta * (1.0 - x * x).sqrt()) / i0_beta;

            coeffs[i] = sinc * kaiser;
        }

        // Normalize for unity gain at DC
        let sum: f64 = coeffs.iter().sum();
        for coeff in &mut coeffs {
            *coeff /= sum;
        }

        coeffs
    }

    /// Modified Bessel function I0 (for Kaiser window)
    fn bessel_i0(x: f64) -> f64 {
        let mut sum = 1.0;
        let mut term = 1.0;

        for k in 1..50 {
            term *= (x / (2.0 * k as f64)).powi(2);
            sum += term;
            if term < 1e-20 {
                break;
            }
        }

        sum
    }

    /// Process samples through this stage
    fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        let mut output = Vec::with_capacity(input.len() / self.factor as usize + 1);

        for &sample in input {
            // Add sample to delay line
            self.delay_line[self.position] = sample;
            self.position = (self.position + 1) % self.delay_line.len();

            // Check if we should output a sample
            self.sample_counter += 1;
            if self.sample_counter >= self.factor {
                self.sample_counter = 0;

                // Compute FIR output
                let mut sum = 0.0;
                for (i, &coeff) in self.coefficients.iter().enumerate() {
                    let idx = (self.position + self.delay_line.len() - 1 - i) % self.delay_line.len();
                    sum += coeff * self.delay_line[idx];
                }

                output.push(sum);
            }
        }

        output
    }

    /// Reset stage state
    fn reset(&mut self) {
        self.delay_line.fill(0.0);
        self.position = 0;
        self.sample_counter = 0;
    }
}

/// Stereo DSD decimator
pub struct StereoDsdDecimator {
    left: DsdDecimator,
    right: DsdDecimator,
}

impl StereoDsdDecimator {
    /// Create stereo decimator
    pub fn new(dsd_rate: f64, output_rate: f64, quality: DecimationQuality) -> Self {
        Self {
            left: DsdDecimator::new(dsd_rate, output_rate, quality),
            right: DsdDecimator::new(dsd_rate, output_rate, quality),
        }
    }

    /// Process stereo DSD to PCM
    pub fn process(
        &mut self,
        left: &[Sample],
        right: &[Sample],
    ) -> (Vec<Sample>, Vec<Sample>) {
        let l = self.left.process(left);
        let r = self.right.process(right);
        (l, r)
    }

    /// Process stereo bits
    pub fn process_bits(
        &mut self,
        left_bits: &[u8],
        right_bits: &[u8],
    ) -> (Vec<Sample>, Vec<Sample>) {
        let l = self.left.process_bits(left_bits);
        let r = self.right.process_bits(right_bits);
        (l, r)
    }

    /// Reset both channels
    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

/// Simple first-order decimation for real-time preview
pub struct FastDecimator {
    /// Accumulator
    accumulator: f64,
    /// Sample count
    count: u32,
    /// Decimation factor
    factor: u32,
}

impl FastDecimator {
    /// Create fast decimator
    pub fn new(factor: u32) -> Self {
        Self {
            accumulator: 0.0,
            count: 0,
            factor,
        }
    }

    /// Process single sample, returns output when available
    pub fn process(&mut self, sample: Sample) -> Option<Sample> {
        self.accumulator += sample;
        self.count += 1;

        if self.count >= self.factor {
            let output = self.accumulator / self.factor as f64;
            self.accumulator = 0.0;
            self.count = 0;
            Some(output)
        } else {
            None
        }
    }

    /// Process block
    pub fn process_block(&mut self, input: &[Sample]) -> Vec<Sample> {
        input.iter()
            .filter_map(|&s| self.process(s))
            .collect()
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.accumulator = 0.0;
        self.count = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_optimal_factors() {
        assert_eq!(DsdDecimator::optimal_factors(64), vec![8, 8]);
        assert_eq!(DsdDecimator::optimal_factors(128), vec![8, 8, 2]);
        assert_eq!(DsdDecimator::optimal_factors(256), vec![8, 8, 4]);
        assert_eq!(DsdDecimator::optimal_factors(512), vec![8, 8, 8]);
    }

    #[test]
    fn test_decimator_creation() {
        let decimator = DsdDecimator::new(2_822_400.0, 44100.0, DecimationQuality::High);
        assert_eq!(decimator.factor(), 64);
    }

    #[test]
    fn test_decimation() {
        let mut decimator = DsdDecimator::new(2_822_400.0, 44100.0, DecimationQuality::Standard);

        // Generate DSD-like signal (alternating +1/-1 for DC-balanced)
        let dsd: Vec<Sample> = (0..640)
            .map(|i| if i % 2 == 0 { 1.0 } else { -1.0 })
            .collect();

        let pcm = decimator.process(&dsd);

        // Should output approximately 640/64 = 10 samples
        assert!(pcm.len() >= 8 && pcm.len() <= 12);
    }

    #[test]
    fn test_decimation_sine() {
        let mut decimator = DsdDecimator::new(2_822_400.0, 44100.0, DecimationQuality::High);

        // Generate 1kHz "DSD sine" (simplified - just modulated +1/-1)
        let samples = 2822; // ~1ms at DSD64
        let dsd: Vec<Sample> = (0..samples)
            .map(|i| {
                let t = i as f64 / 2_822_400.0;
                let sine = (2.0 * PI * 1000.0 * t).sin();
                if sine >= 0.0 { 1.0 } else { -1.0 }
            })
            .collect();

        let pcm = decimator.process(&dsd);

        // Should output approximately samples/64 PCM samples
        let expected = samples / 64;
        assert!(
            pcm.len() >= expected - 5 && pcm.len() <= expected + 5,
            "Expected ~{} samples, got {}",
            expected,
            pcm.len()
        );
    }

    #[test]
    fn test_fast_decimator() {
        let mut decimator = FastDecimator::new(8);

        let input = vec![1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0];
        let output = decimator.process_block(&input);

        assert_eq!(output.len(), 1);
        // (4 * 1.0 + 4 * -1.0) / 8 = 0
        assert!((output[0]).abs() < 0.001);
    }

    #[test]
    fn test_stereo_decimator() {
        let mut decimator = StereoDsdDecimator::new(
            2_822_400.0,
            44100.0,
            DecimationQuality::Standard,
        );

        let left: Vec<Sample> = (0..640).map(|i| if i % 2 == 0 { 1.0 } else { -1.0 }).collect();
        let right: Vec<Sample> = (0..640).map(|i| if i % 2 == 1 { 1.0 } else { -1.0 }).collect();

        let (l, r) = decimator.process(&left, &right);

        assert_eq!(l.len(), r.len());
    }

    #[test]
    fn test_quality_levels() {
        assert!(DecimationQuality::Ultimate.filter_order() > DecimationQuality::High.filter_order());
        assert!(DecimationQuality::High.filter_order() > DecimationQuality::Standard.filter_order());
        assert!(DecimationQuality::Standard.filter_order() > DecimationQuality::Fast.filter_order());
    }
}
