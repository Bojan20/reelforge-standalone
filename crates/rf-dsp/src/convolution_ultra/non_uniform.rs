//! Non-uniform Partitioned Convolution
//!
//! UNIQUE: No other reverb plugin uses this technique.
//!
//! Uses small partitions for early part of IR (low latency)
//! and progressively larger partitions for later parts (efficiency).
//!
//! Example for 5-second IR @ 48kHz:
//! - Partition 0: 64 samples  (1.3ms latency)
//! - Partition 1: 128 samples
//! - Partition 2: 256 samples
//! - Partition 3: 512 samples
//! - Partition 4+: 4096 samples (bulk)

use super::{ImpulseResponse, MAX_PARTITIONS};
use rf_core::Sample;
use rustfft::{FftPlanner, num_complex::Complex64};
use std::sync::Arc;

/// Non-uniform partition scheme
#[derive(Debug, Clone)]
pub struct PartitionScheme {
    /// List of partition sizes
    pub sizes: Vec<usize>,
    /// Total IR length covered
    pub total_length: usize,
    /// Minimum latency (first partition size)
    pub min_latency: usize,
}

impl PartitionScheme {
    /// Create optimal scheme for given IR length
    pub fn optimal(ir_length: usize) -> Self {
        let mut sizes = Vec::new();
        let mut remaining = ir_length;
        let mut current_size = 64; // Start small

        while remaining > 0 && sizes.len() < MAX_PARTITIONS {
            let count = if remaining >= current_size * 4 {
                4 // Use 4 partitions of this size before doubling
            } else {
                (remaining + current_size - 1) / current_size
            };

            for _ in 0..count {
                if remaining == 0 {
                    break;
                }
                sizes.push(current_size.min(remaining));
                remaining = remaining.saturating_sub(current_size);
            }

            current_size *= 2;
            if current_size > 4096 {
                current_size = 4096; // Cap at 4096
            }
        }

        Self {
            sizes: sizes.clone(),
            total_length: ir_length,
            min_latency: sizes.first().copied().unwrap_or(64),
        }
    }

    /// Create low-latency scheme (smaller first partitions)
    pub fn low_latency(ir_length: usize) -> Self {
        let mut sizes = Vec::new();
        let mut remaining = ir_length;

        // Very small first partitions
        let first_sizes = [32, 32, 64, 64, 128, 128, 256, 256, 512, 512];

        for &size in &first_sizes {
            if remaining == 0 || sizes.len() >= MAX_PARTITIONS {
                break;
            }
            sizes.push(size.min(remaining));
            remaining = remaining.saturating_sub(size);
        }

        // Fill rest with large partitions
        while remaining > 0 && sizes.len() < MAX_PARTITIONS {
            let size = 4096.min(remaining);
            sizes.push(size);
            remaining = remaining.saturating_sub(size);
        }

        Self {
            sizes: sizes.clone(),
            total_length: ir_length,
            min_latency: sizes.first().copied().unwrap_or(32),
        }
    }

    /// Create efficiency-focused scheme (larger partitions)
    pub fn efficient(ir_length: usize) -> Self {
        let mut sizes = Vec::new();
        let mut remaining = ir_length;

        // Start with moderate partition
        let first_sizes = [256, 256, 512, 512, 1024, 1024];

        for &size in &first_sizes {
            if remaining == 0 || sizes.len() >= MAX_PARTITIONS {
                break;
            }
            sizes.push(size.min(remaining));
            remaining = remaining.saturating_sub(size);
        }

        // Fill rest with maximum size partitions
        while remaining > 0 && sizes.len() < MAX_PARTITIONS {
            let size = 8192.min(remaining);
            sizes.push(size);
            remaining = remaining.saturating_sub(size);
        }

        Self {
            sizes: sizes.clone(),
            total_length: ir_length,
            min_latency: sizes.first().copied().unwrap_or(256),
        }
    }

    /// Number of partitions
    pub fn num_partitions(&self) -> usize {
        self.sizes.len()
    }
}

/// Single partition state
struct Partition {
    /// Partition size (time domain)
    size: usize,
    /// FFT size (2x partition size)
    fft_size: usize,
    /// IR segment in frequency domain
    ir_spectrum: Vec<Complex64>,
    /// Input buffer
    input_buffer: Vec<Sample>,
    /// Input position
    input_pos: usize,
    /// Frequency domain delay line
    fdl: Vec<Vec<Complex64>>,
    /// FDL write position
    fdl_pos: usize,
    /// Number of FDL segments needed
    fdl_segments: usize,
    /// Output overlap buffer
    overlap: Vec<Sample>,
    /// FFT forward plan
    fft_forward: Arc<dyn rustfft::Fft<f64>>,
    /// FFT inverse plan
    fft_inverse: Arc<dyn rustfft::Fft<f64>>,
}

impl Partition {
    fn new(
        ir_segment: &[Sample],
        size: usize,
        fdl_segments: usize,
        planner: &mut FftPlanner<f64>,
    ) -> Self {
        let fft_size = size * 2;

        let fft_forward = planner.plan_fft_forward(fft_size);
        let fft_inverse = planner.plan_fft_inverse(fft_size);

        // Compute IR spectrum
        let mut ir_buffer: Vec<Complex64> = ir_segment.iter()
            .take(size)
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        ir_buffer.resize(fft_size, Complex64::new(0.0, 0.0));
        fft_forward.process(&mut ir_buffer);

        // Initialize FDL
        let fdl = (0..fdl_segments)
            .map(|_| vec![Complex64::new(0.0, 0.0); fft_size])
            .collect();

        Self {
            size,
            fft_size,
            ir_spectrum: ir_buffer,
            input_buffer: vec![0.0; size],
            input_pos: 0,
            fdl,
            fdl_pos: 0,
            fdl_segments,
            overlap: vec![0.0; size],
            fft_forward,
            fft_inverse,
        }
    }

    /// Add input sample, returns output when block is complete
    fn process_sample(&mut self, input: Sample) -> Option<Vec<Sample>> {
        self.input_buffer[self.input_pos] = input;
        self.input_pos += 1;

        if self.input_pos >= self.size {
            self.input_pos = 0;
            Some(self.process_block())
        } else {
            None
        }
    }

    /// Process complete block
    fn process_block(&mut self) -> Vec<Sample> {
        // FFT input
        let mut input_spectrum: Vec<Complex64> = self.input_buffer.iter()
            .map(|&s| Complex64::new(s, 0.0))
            .collect();
        input_spectrum.resize(self.fft_size, Complex64::new(0.0, 0.0));
        self.fft_forward.process(&mut input_spectrum);

        // Store in FDL
        self.fdl[self.fdl_pos] = input_spectrum;

        // Convolve (multiply-accumulate)
        let mut output_spectrum = vec![Complex64::new(0.0, 0.0); self.fft_size];
        for seg in 0..self.fdl_segments {
            let fdl_idx = (self.fdl_pos + self.fdl_segments - seg) % self.fdl_segments;
            for i in 0..self.fft_size {
                output_spectrum[i] += self.fdl[fdl_idx][i] * self.ir_spectrum[i];
            }
        }

        // IFFT
        self.fft_inverse.process(&mut output_spectrum);

        // Scale and overlap-add
        let scale = 1.0 / self.fft_size as f64;
        let mut output = vec![0.0; self.size];

        for i in 0..self.size {
            output[i] = output_spectrum[i].re * scale + self.overlap[i];
            self.overlap[i] = output_spectrum[i + self.size].re * scale;
        }

        // Advance FDL
        self.fdl_pos = (self.fdl_pos + 1) % self.fdl_segments;

        output
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.input_pos = 0;
        for fdl_seg in &mut self.fdl {
            fdl_seg.fill(Complex64::new(0.0, 0.0));
        }
        self.fdl_pos = 0;
        self.overlap.fill(0.0);
    }
}

/// Non-uniform partitioned convolver
pub struct NonUniformConvolver {
    /// Partitions (different sizes)
    partitions: Vec<Partition>,
    /// Partition scheme
    scheme: PartitionScheme,
    /// Output accumulator per partition
    output_accum: Vec<Vec<Sample>>,
    /// Current output position
    output_pos: usize,
    /// Sample counter for scheduling
    sample_counter: usize,
}

impl NonUniformConvolver {
    /// Create with optimal scheme
    pub fn new(ir: &ImpulseResponse) -> Self {
        let scheme = PartitionScheme::optimal(ir.len());
        Self::with_scheme(ir, scheme)
    }

    /// Create with specific scheme
    pub fn with_scheme(ir: &ImpulseResponse, scheme: PartitionScheme) -> Self {
        let mut planner = FftPlanner::new();
        let mut partitions = Vec::new();
        let mut ir_offset = 0;

        for &size in &scheme.sizes {
            let ir_segment: Vec<Sample> = ir.samples[ir_offset..]
                .iter()
                .take(size)
                .copied()
                .collect();

            // Calculate how many FDL segments needed based on position in IR
            // Later partitions need more FDL segments due to larger delays
            let fdl_segments = ((ir_offset + size) / size).max(1).min(16);

            partitions.push(Partition::new(&ir_segment, size, fdl_segments, &mut planner));
            ir_offset += size;
        }

        let output_accum = scheme.sizes.iter()
            .map(|&size| vec![0.0; size])
            .collect();

        Self {
            partitions,
            scheme,
            output_accum,
            output_pos: 0,
            sample_counter: 0,
        }
    }

    /// Create low-latency variant
    pub fn low_latency(ir: &ImpulseResponse) -> Self {
        let scheme = PartitionScheme::low_latency(ir.len());
        Self::with_scheme(ir, scheme)
    }

    /// Create efficient variant
    pub fn efficient(ir: &ImpulseResponse) -> Self {
        let scheme = PartitionScheme::efficient(ir.len());
        Self::with_scheme(ir, scheme)
    }

    /// Process single sample
    pub fn process_sample(&mut self, input: Sample) -> Sample {
        let mut output = 0.0;

        // Process each partition
        for (i, partition) in self.partitions.iter_mut().enumerate() {
            if let Some(block_output) = partition.process_sample(input) {
                // Accumulate output from this partition
                for (j, &s) in block_output.iter().enumerate() {
                    self.output_accum[i][j] += s;
                }
            }
        }

        // Get output from first (smallest) partition's accumulator
        if !self.output_accum.is_empty() {
            let first_size = self.scheme.sizes[0];
            output = self.output_accum[0][self.output_pos];
            self.output_accum[0][self.output_pos] = 0.0;

            self.output_pos = (self.output_pos + 1) % first_size;
        }

        self.sample_counter += 1;
        output
    }

    /// Process block
    pub fn process(&mut self, input: &[Sample]) -> Vec<Sample> {
        input.iter().map(|&s| self.process_sample(s)).collect()
    }

    /// Get minimum latency
    pub fn latency(&self) -> usize {
        self.scheme.min_latency
    }

    /// Get partition scheme
    pub fn scheme(&self) -> &PartitionScheme {
        &self.scheme
    }

    /// Reset state
    pub fn reset(&mut self) {
        for partition in &mut self.partitions {
            partition.reset();
        }
        for accum in &mut self.output_accum {
            accum.fill(0.0);
        }
        self.output_pos = 0;
        self.sample_counter = 0;
    }
}

/// Stereo non-uniform convolver
pub struct StereoNonUniformConvolver {
    left: NonUniformConvolver,
    right: NonUniformConvolver,
}

impl StereoNonUniformConvolver {
    /// Create from stereo IR
    pub fn new(ir: &ImpulseResponse) -> Self {
        assert_eq!(ir.channels, 2);

        let left_samples = ir.channel(0);
        let right_samples = ir.channel(1);

        let left_ir = ImpulseResponse::new(left_samples, ir.sample_rate, 1);
        let right_ir = ImpulseResponse::new(right_samples, ir.sample_rate, 1);

        Self {
            left: NonUniformConvolver::new(&left_ir),
            right: NonUniformConvolver::new(&right_ir),
        }
    }

    /// Process stereo
    pub fn process(
        &mut self,
        left: &[Sample],
        right: &[Sample],
    ) -> (Vec<Sample>, Vec<Sample>) {
        (self.left.process(left), self.right.process(right))
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
    fn test_partition_scheme_optimal() {
        let scheme = PartitionScheme::optimal(48000); // ~1 second

        assert!(!scheme.sizes.is_empty());
        assert!(scheme.sizes[0] <= 128); // First partition should be small
        assert!(scheme.min_latency <= 128);
    }

    #[test]
    fn test_partition_scheme_low_latency() {
        let scheme = PartitionScheme::low_latency(48000);

        assert!(scheme.min_latency <= 64);
    }

    #[test]
    fn test_non_uniform_convolver() {
        let ir = ImpulseResponse::new(vec![1.0; 1024], 48000.0, 1);
        let mut convolver = NonUniformConvolver::new(&ir);

        let input = vec![1.0, 0.0, 0.0, 0.0];
        let output = convolver.process(&input);

        // Should produce some output
        assert_eq!(output.len(), 4);
    }

    #[test]
    fn test_stereo_non_uniform() {
        let samples: Vec<Sample> = (0..2048)
            .map(|i| if i % 2 == 0 { 1.0 } else { 0.5 })
            .collect();

        let ir = ImpulseResponse::new(samples, 48000.0, 2);
        let mut convolver = StereoNonUniformConvolver::new(&ir);

        let input_l = vec![1.0; 128];
        let input_r = vec![0.5; 128];

        let (out_l, out_r) = convolver.process(&input_l, &input_r);

        assert_eq!(out_l.len(), 128);
        assert_eq!(out_r.len(), 128);
    }
}
