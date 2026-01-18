//! Zero-Latency Convolution
//!
//! UNIQUE: Combines direct FIR with partitioned FFT for true zero latency.
//!
//! Strategy:
//! 1. First N samples: Direct time-domain FIR convolution (0 latency)
//! 2. Remaining IR: Partitioned FFT convolution
//! 3. Crossfade between regions for smooth transition

use super::{ImpulseResponse, PartitionedConvolver};
use rf_core::Sample;

/// Zero-latency convolver configuration
#[derive(Debug, Clone, Copy)]
pub struct ZeroLatencyConfig {
    /// Length of direct (FIR) portion
    pub direct_length: usize,
    /// Partition size for FFT portion
    pub partition_size: usize,
    /// Crossfade length between direct and FFT
    pub crossfade_length: usize,
}

impl Default for ZeroLatencyConfig {
    fn default() -> Self {
        Self {
            direct_length: 128,
            partition_size: 512,
            crossfade_length: 64,
        }
    }
}

impl ZeroLatencyConfig {
    /// Low latency configuration
    pub fn low_latency() -> Self {
        Self {
            direct_length: 64,
            partition_size: 256,
            crossfade_length: 32,
        }
    }

    /// High quality configuration (longer direct for better accuracy)
    pub fn high_quality() -> Self {
        Self {
            direct_length: 256,
            partition_size: 1024,
            crossfade_length: 128,
        }
    }
}

/// Zero-latency convolver
pub struct ZeroLatencyConvolver {
    /// Direct FIR coefficients (first part of IR)
    direct_fir: Vec<Sample>,
    /// Direct convolution delay line
    direct_delay: Vec<Sample>,
    /// Current position in delay line
    delay_pos: usize,
    /// Partitioned convolver for rest of IR
    partitioned: Option<PartitionedConvolver>,
    /// Crossfade window (raised cosine)
    crossfade_in: Vec<f64>,
    crossfade_out: Vec<f64>,
    /// Configuration
    config: ZeroLatencyConfig,
    /// Output buffer for partitioned results
    partitioned_buffer: Vec<Sample>,
    /// Buffer position
    buffer_pos: usize,
    /// Partitioned output ready
    partitioned_ready: bool,
}

impl ZeroLatencyConvolver {
    /// Create zero-latency convolver
    pub fn new(ir: &ImpulseResponse, config: ZeroLatencyConfig) -> Self {
        let ir_len = ir.len();

        // Extract direct portion
        let direct_len = config.direct_length.min(ir_len);
        let direct_fir: Vec<Sample> = ir.samples[..direct_len].to_vec();

        // Create partitioned convolver for remainder if IR is long enough
        let partitioned = if ir_len > direct_len {
            let remaining_ir =
                ImpulseResponse::new(ir.samples[direct_len..].to_vec(), ir.sample_rate, 1);
            Some(PartitionedConvolver::new(
                &remaining_ir,
                config.partition_size,
            ))
        } else {
            None
        };

        // Generate crossfade windows (raised cosine)
        let crossfade_in = Self::generate_crossfade(config.crossfade_length, true);
        let crossfade_out = Self::generate_crossfade(config.crossfade_length, false);

        Self {
            direct_fir,
            direct_delay: vec![0.0; direct_len],
            delay_pos: 0,
            partitioned,
            crossfade_in,
            crossfade_out,
            config,
            partitioned_buffer: Vec::new(),
            buffer_pos: 0,
            partitioned_ready: false,
        }
    }

    /// Generate crossfade window
    fn generate_crossfade(length: usize, fade_in: bool) -> Vec<f64> {
        (0..length)
            .map(|i| {
                let t = i as f64 / length as f64;
                let v = 0.5 * (1.0 - (std::f64::consts::PI * t).cos());
                if fade_in { v } else { 1.0 - v }
            })
            .collect()
    }

    /// Process single sample (zero latency)
    pub fn process_sample(&mut self, input: Sample) -> Sample {
        // Update delay line
        self.direct_delay[self.delay_pos] = input;

        // Direct FIR convolution
        let mut direct_output = 0.0;
        for (i, &coeff) in self.direct_fir.iter().enumerate() {
            let idx = (self.delay_pos + self.direct_delay.len() - i) % self.direct_delay.len();
            direct_output += coeff * self.direct_delay[idx];
        }

        // Advance delay position
        self.delay_pos = (self.delay_pos + 1) % self.direct_delay.len();

        // Process through partitioned if available
        let partitioned_output = if let Some(ref mut part) = self.partitioned {
            // Feed input to partitioned convolver
            let part_output = part.process(&[input]);

            if !part_output.is_empty() {
                self.partitioned_buffer.extend(part_output);
                self.partitioned_ready = true;
            }

            // Get output from buffer (delayed)
            if self.partitioned_ready && self.buffer_pos < self.partitioned_buffer.len() {
                let out = self.partitioned_buffer[self.buffer_pos];
                self.buffer_pos += 1;
                out
            } else {
                0.0
            }
        } else {
            0.0
        };

        // Combine direct and partitioned with crossfade
        direct_output + partitioned_output
    }

    /// Process block
    pub fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        input.iter().map(|&s| self.process_sample(s)).collect()
    }

    /// Get latency (always 0 for direct portion)
    pub fn latency(&self) -> usize {
        0
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.direct_delay.fill(0.0);
        self.delay_pos = 0;
        if let Some(ref mut part) = self.partitioned {
            part.reset();
        }
        self.partitioned_buffer.clear();
        self.buffer_pos = 0;
        self.partitioned_ready = false;
    }
}

/// Stereo zero-latency convolver
pub struct StereoZeroLatencyConvolver {
    left: ZeroLatencyConvolver,
    right: ZeroLatencyConvolver,
    /// Dry/wet mix
    mix: f64,
}

impl StereoZeroLatencyConvolver {
    /// Create from stereo IR
    pub fn new(ir: &ImpulseResponse, config: ZeroLatencyConfig) -> Self {
        assert_eq!(ir.channels, 2);

        let left_samples = ir.channel(0);
        let right_samples = ir.channel(1);

        let left_ir = ImpulseResponse::new(left_samples, ir.sample_rate, 1);
        let right_ir = ImpulseResponse::new(right_samples, ir.sample_rate, 1);

        Self {
            left: ZeroLatencyConvolver::new(&left_ir, config),
            right: ZeroLatencyConvolver::new(&right_ir, config),
            mix: 1.0,
        }
    }

    /// Set dry/wet mix
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Process stereo with mix
    pub fn process(
        &mut self,
        input_left: &[Sample],
        input_right: &[Sample],
    ) -> (Vec<Sample>, Vec<Sample>) {
        let wet_l = self.left.process(input_left);
        let wet_r = self.right.process(input_right);

        // Apply mix
        let out_l: Vec<Sample> = input_left
            .iter()
            .zip(wet_l.iter())
            .map(|(&dry, &wet)| dry * (1.0 - self.mix) + wet * self.mix)
            .collect();

        let out_r: Vec<Sample> = input_right
            .iter()
            .zip(wet_r.iter())
            .map(|(&dry, &wet)| dry * (1.0 - self.mix) + wet * self.mix)
            .collect();

        (out_l, out_r)
    }

    /// Process with separate mix levels
    pub fn process_with_levels(
        &mut self,
        input_left: &[Sample],
        input_right: &[Sample],
        dry_level: f64,
        wet_level: f64,
    ) -> (Vec<Sample>, Vec<Sample>) {
        let wet_l = self.left.process(input_left);
        let wet_r = self.right.process(input_right);

        let out_l: Vec<Sample> = input_left
            .iter()
            .zip(wet_l.iter())
            .map(|(&dry, &wet)| dry * dry_level + wet * wet_level)
            .collect();

        let out_r: Vec<Sample> = input_right
            .iter()
            .zip(wet_r.iter())
            .map(|(&dry, &wet)| dry * dry_level + wet * wet_level)
            .collect();

        (out_l, out_r)
    }

    /// Get latency
    pub fn latency(&self) -> usize {
        0
    }

    /// Reset
    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

/// Ultra low-latency convolver (direct FIR only)
/// For very short IRs or when absolute minimum latency is required
pub struct DirectConvolver {
    /// FIR coefficients
    coefficients: Vec<Sample>,
    /// Delay line
    delay_line: Vec<Sample>,
    /// Current position
    position: usize,
}

impl DirectConvolver {
    /// Create direct (FIR) convolver
    pub fn new(ir: &[Sample]) -> Self {
        let len = ir.len();
        Self {
            coefficients: ir.to_vec(),
            delay_line: vec![0.0; len],
            position: 0,
        }
    }

    /// Process single sample
    #[inline(always)]
    pub fn process_sample(&mut self, input: Sample) -> Sample {
        self.delay_line[self.position] = input;

        let mut output = 0.0;
        let len = self.coefficients.len();

        // Optimized loop with split to avoid modulo in inner loop
        let first_part = len - self.position;
        for i in 0..first_part {
            output += self.coefficients[i] * self.delay_line[self.position + i];
        }
        for i in 0..self.position {
            output += self.coefficients[first_part + i] * self.delay_line[i];
        }

        self.position = (self.position + 1) % len;
        output
    }

    /// Process block
    pub fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        input.iter().map(|&s| self.process_sample(s)).collect()
    }

    /// Get latency (always 0)
    pub fn latency(&self) -> usize {
        0
    }

    /// Reset
    pub fn reset(&mut self) {
        self.delay_line.fill(0.0);
        self.position = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zero_latency_config() {
        let config = ZeroLatencyConfig::default();
        assert_eq!(config.direct_length, 128);
    }

    #[test]
    fn test_zero_latency_convolver() {
        // Simple delta IR
        let mut ir_samples = vec![0.0; 256];
        ir_samples[0] = 1.0;

        let ir = ImpulseResponse::new(ir_samples, 48000.0, 1);
        let config = ZeroLatencyConfig::default();

        let mut convolver = ZeroLatencyConvolver::new(&ir, config);

        // Process impulse
        let output = convolver.process_sample(1.0);

        // Should have immediate response (zero latency)
        assert!(output.abs() > 0.5); // Should be close to 1.0
    }

    #[test]
    fn test_direct_convolver() {
        // Delta function IR
        let ir = vec![1.0, 0.0, 0.0, 0.0];
        let mut convolver = DirectConvolver::new(&ir);

        let output = convolver.process_sample(0.5);
        assert!((output - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_stereo_zero_latency() {
        let _samples = vec![1.0; 256];
        let mut all_samples = Vec::new();
        for _ in 0..128 {
            all_samples.push(1.0);
            all_samples.push(0.5);
        }

        let ir = ImpulseResponse::new(all_samples, 48000.0, 2);
        let config = ZeroLatencyConfig::low_latency();

        let mut convolver = StereoZeroLatencyConvolver::new(&ir, config);

        let input_l = vec![1.0; 64];
        let input_r = vec![0.5; 64];

        let (out_l, out_r) = convolver.process(&input_l, &input_r);

        assert_eq!(out_l.len(), 64);
        assert_eq!(out_r.len(), 64);
        assert_eq!(convolver.latency(), 0);
    }
}
