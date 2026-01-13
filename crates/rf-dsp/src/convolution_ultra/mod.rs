//! Convolution ULTIMATE Module
//!
//! Professional convolution reverb beyond any competitor:
//! - True Stereo (4-channel IR)
//! - Non-uniform Partitioned (optimal latency/quality)
//! - Zero-latency mode (direct + partitioned)
//! - IR Morphing (spectral crossfade)
//! - IR Deconvolution (sweep → IR extraction)

pub mod deconvolve;
pub mod morph;
pub mod non_uniform;
pub mod true_stereo;
pub mod zero_latency;

pub use deconvolve::*;
pub use morph::*;
pub use non_uniform::*;
pub use true_stereo::*;
pub use zero_latency::*;

use rf_core::Sample;
use rustfft::{FftPlanner, num_complex::Complex64};

/// Maximum IR length supported (10 seconds @ 192kHz)
pub const MAX_IR_LENGTH: usize = 1_920_000;

/// Maximum number of partitions
pub const MAX_PARTITIONS: usize = 64;

/// Impulse Response container
#[derive(Clone)]
pub struct ImpulseResponse {
    /// Time-domain samples
    pub samples: Vec<Sample>,
    /// Sample rate
    pub sample_rate: f64,
    /// Number of channels
    pub channels: u8,
    /// Pre-computed spectrum for fast loading
    pub spectrum: Option<Vec<Complex64>>,
}

impl ImpulseResponse {
    /// Create new IR from samples
    pub fn new(samples: Vec<Sample>, sample_rate: f64, channels: u8) -> Self {
        Self {
            samples,
            sample_rate,
            channels,
            spectrum: None,
        }
    }

    /// Create stereo IR from L/R
    pub fn stereo(left: Vec<Sample>, right: Vec<Sample>, sample_rate: f64) -> Self {
        assert_eq!(left.len(), right.len());
        let mut samples = Vec::with_capacity(left.len() * 2);
        for (l, r) in left.into_iter().zip(right.into_iter()) {
            samples.push(l);
            samples.push(r);
        }
        Self::new(samples, sample_rate, 2)
    }

    /// Length in samples (per channel)
    pub fn len(&self) -> usize {
        self.samples.len() / self.channels as usize
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        self.len() as f64 / self.sample_rate
    }

    /// Get channel data
    pub fn channel(&self, ch: u8) -> Vec<Sample> {
        if ch >= self.channels {
            return Vec::new();
        }

        let len = self.len();
        (0..len)
            .map(|i| self.samples[i * self.channels as usize + ch as usize])
            .collect()
    }

    /// Pre-compute FFT spectrum
    pub fn precompute_spectrum(&mut self, fft_size: usize) {
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        // Pad to FFT size
        let mut buffer: Vec<Complex64> = self
            .samples
            .iter()
            .take(fft_size)
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        buffer.resize(fft_size, Complex64::new(0.0, 0.0));

        fft.process(&mut buffer);
        self.spectrum = Some(buffer);
    }

    /// Normalize IR to unit peak
    pub fn normalize(&mut self) {
        let peak = self.samples.iter().map(|s| s.abs()).fold(0.0, f64::max);

        if peak > 0.0 {
            for s in &mut self.samples {
                *s /= peak;
            }
        }
    }

    /// Trim silence from end
    pub fn trim(&mut self, threshold_db: f64) {
        let threshold = 10.0_f64.powf(threshold_db / 20.0);

        // Find last sample above threshold
        let mut last_idx = self.samples.len();
        for (i, &s) in self.samples.iter().enumerate().rev() {
            if s.abs() > threshold {
                last_idx = i + 1;
                break;
            }
        }

        // Round up to next power of 2 for FFT efficiency
        let new_len = last_idx.next_power_of_two().min(self.samples.len());
        self.samples.truncate(new_len);
    }
}

/// Basic partitioned convolver (uniform partitions)
pub struct PartitionedConvolver {
    /// FFT size
    fft_size: usize,
    /// Number of partitions
    num_partitions: usize,
    /// IR partitions in frequency domain
    ir_partitions: Vec<Vec<Complex64>>,
    /// Input buffer
    input_buffer: Vec<Sample>,
    /// Frequency Domain Delay Line
    fdl: Vec<Vec<Complex64>>,
    /// Output overlap buffer
    overlap: Vec<Sample>,
    /// FFT planner
    fft_forward: std::sync::Arc<dyn rustfft::Fft<f64>>,
    fft_inverse: std::sync::Arc<dyn rustfft::Fft<f64>>,
    /// Current position in input buffer
    input_pos: usize,
    /// Current FDL index
    fdl_index: usize,
}

impl PartitionedConvolver {
    /// Create new partitioned convolver
    pub fn new(ir: &ImpulseResponse, partition_size: usize) -> Self {
        let fft_size = partition_size * 2;
        let ir_len = ir.len();
        let num_partitions = ir_len.div_ceil(partition_size);

        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Partition IR and compute spectra
        let mut ir_partitions = Vec::with_capacity(num_partitions);
        for p in 0..num_partitions {
            let start = p * partition_size;
            let end = (start + partition_size).min(ir_len);

            let mut buffer: Vec<Complex64> = ir.samples[start..end]
                .iter()
                .map(|&s| Complex64::new(s, 0.0))
                .collect();
            buffer.resize(fft_size, Complex64::new(0.0, 0.0));

            fft_forward.process(&mut buffer);
            ir_partitions.push(buffer);
        }

        // Initialize FDL
        let fdl = (0..num_partitions)
            .map(|_| vec![Complex64::new(0.0, 0.0); fft_size])
            .collect();

        Self {
            fft_size,
            num_partitions,
            ir_partitions,
            input_buffer: vec![0.0; partition_size],
            fdl,
            overlap: vec![0.0; partition_size],
            fft_forward,
            fft_inverse,
            input_pos: 0,
            fdl_index: 0,
        }
    }

    /// Process block
    pub fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        let partition_size = self.fft_size / 2;
        let mut output = Vec::with_capacity(input.len());

        for &sample in input {
            self.input_buffer[self.input_pos] = sample;
            self.input_pos += 1;

            if self.input_pos >= partition_size {
                // Process this partition
                let block_output = self.process_partition();
                output.extend_from_slice(&block_output);
                self.input_pos = 0;
            }
        }

        output
    }

    /// Process one partition
    fn process_partition(&mut self) -> Vec<Sample> {
        let partition_size = self.fft_size / 2;

        // FFT input block (with zero padding)
        let mut input_spectrum: Vec<Complex64> = self
            .input_buffer
            .iter()
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        input_spectrum.resize(self.fft_size, Complex64::new(0.0, 0.0));
        self.fft_forward.process(&mut input_spectrum);

        // Update FDL (circular)
        self.fdl[self.fdl_index] = input_spectrum;

        // Multiply-accumulate all partitions
        let mut output_spectrum = vec![Complex64::new(0.0, 0.0); self.fft_size];
        for p in 0..self.num_partitions {
            let fdl_idx = (self.fdl_index + self.num_partitions - p) % self.num_partitions;
            for i in 0..self.fft_size {
                output_spectrum[i] += self.fdl[fdl_idx][i] * self.ir_partitions[p][i];
            }
        }

        // IFFT
        self.fft_inverse.process(&mut output_spectrum);

        // Scale and overlap-add
        let scale = 1.0 / self.fft_size as f64;
        let mut output = vec![0.0; partition_size];
        for i in 0..partition_size {
            output[i] = output_spectrum[i].re * scale + self.overlap[i];
            self.overlap[i] = output_spectrum[i + partition_size].re * scale;
        }

        // Advance FDL index
        self.fdl_index = (self.fdl_index + 1) % self.num_partitions;

        output
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.fft_size / 2
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        for fdl_entry in &mut self.fdl {
            fdl_entry.fill(Complex64::new(0.0, 0.0));
        }
        self.overlap.fill(0.0);
        self.input_pos = 0;
        self.fdl_index = 0;
    }
}

/// Stereo partitioned convolver
pub struct StereoPartitionedConvolver {
    left: PartitionedConvolver,
    right: PartitionedConvolver,
}

impl StereoPartitionedConvolver {
    /// Create from stereo IR
    pub fn new(ir: &ImpulseResponse, partition_size: usize) -> Self {
        assert_eq!(ir.channels, 2);

        let left_samples: Vec<Sample> = ir.channel(0);
        let right_samples: Vec<Sample> = ir.channel(1);

        let left_ir = ImpulseResponse::new(left_samples, ir.sample_rate, 1);
        let right_ir = ImpulseResponse::new(right_samples, ir.sample_rate, 1);

        Self {
            left: PartitionedConvolver::new(&left_ir, partition_size),
            right: PartitionedConvolver::new(&right_ir, partition_size),
        }
    }

    /// Process stereo
    pub fn process(&mut self, left: &[Sample], right: &[Sample]) -> (Vec<Sample>, Vec<Sample>) {
        let l = self.left.process(left);
        let r = self.right.process(right);
        (l, r)
    }

    /// Get latency
    pub fn latency(&self) -> usize {
        self.left.latency()
    }

    /// Reset
    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ir_creation() {
        let samples = vec![1.0, 0.5, 0.25, 0.125];
        let ir = ImpulseResponse::new(samples, 44100.0, 1);

        assert_eq!(ir.len(), 4);
        assert!((ir.duration() - 4.0 / 44100.0).abs() < 1e-10);
    }

    #[test]
    fn test_ir_normalize() {
        let mut ir = ImpulseResponse::new(vec![0.5, -1.0, 0.25], 44100.0, 1);
        ir.normalize();

        let peak = ir.samples.iter().map(|s| s.abs()).fold(0.0, f64::max);
        assert!((peak - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_convolver_creation() {
        let ir = ImpulseResponse::new(vec![1.0; 1024], 44100.0, 1);
        let convolver = PartitionedConvolver::new(&ir, 512);

        assert_eq!(convolver.latency(), 512);
    }

    #[test]
    fn test_convolver_process() {
        // Simple delta function IR
        let mut ir_samples = vec![0.0; 512];
        ir_samples[0] = 1.0;
        let ir = ImpulseResponse::new(ir_samples, 44100.0, 1);

        let mut convolver = PartitionedConvolver::new(&ir, 256);

        // Process impulse
        let input = vec![1.0, 0.0, 0.0, 0.0];
        let _ = convolver.process(&input);
    }
}
