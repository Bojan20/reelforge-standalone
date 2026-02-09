//! Reverb processors
//!
//! Includes:
//! - Convolution reverb (IR-based)
//! - Algorithmic reverb (plate, hall, room)

use rf_core::Sample;
use rustfft::{FftPlanner, num_complex::Complex};
use std::sync::Arc;

use crate::{Processor, ProcessorConfig, StereoProcessor};

/// Partition size for convolution (uniform partitioned convolution)
const PARTITION_SIZE: usize = 256;

/// Convolution reverb using uniform partitioned convolution
///
/// Uses overlap-save method with FFT for efficient convolution
/// of long impulse responses.
pub struct ConvolutionReverb {
    // Impulse response partitions (frequency domain)
    ir_partitions_l: Vec<Vec<Complex<f64>>>,
    ir_partitions_r: Vec<Vec<Complex<f64>>>,

    // Input buffer history
    input_buffer_l: Vec<Sample>,
    input_buffer_r: Vec<Sample>,

    // Frequency domain accumulators
    accum_l: Vec<Complex<f64>>,
    accum_r: Vec<Complex<f64>>,

    // Output overlap buffer
    overlap_l: Vec<Sample>,
    overlap_r: Vec<Sample>,

    // Processing state
    buffer_pos: usize,
    partition_index: usize,

    // Parameters
    dry_wet: f64,
    predelay_samples: usize,
    predelay_buffer_l: Vec<Sample>,
    predelay_buffer_r: Vec<Sample>,
    predelay_pos: usize,

    sample_rate: f64,
    ir_loaded: bool,

    // FFT processors (rustfft for O(n log n) performance)
    fft: Arc<dyn rustfft::Fft<f64>>,
    ifft: Arc<dyn rustfft::Fft<f64>>,
    // Scratch buffer for FFT (avoid allocations in audio thread)
    fft_scratch: Vec<Complex<f64>>,
}

impl ConvolutionReverb {
    pub fn new(sample_rate: f64) -> Self {
        let fft_size = PARTITION_SIZE * 2;

        // Create FFT planner (O(n log n) instead of naive O(n²))
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);
        let ifft = planner.plan_fft_inverse(fft_size);
        let scratch_len = fft
            .get_inplace_scratch_len()
            .max(ifft.get_inplace_scratch_len());

        Self {
            ir_partitions_l: Vec::new(),
            ir_partitions_r: Vec::new(),
            input_buffer_l: vec![0.0; fft_size],
            input_buffer_r: vec![0.0; fft_size],
            accum_l: vec![Complex::new(0.0, 0.0); fft_size],
            accum_r: vec![Complex::new(0.0, 0.0); fft_size],
            overlap_l: vec![0.0; PARTITION_SIZE],
            overlap_r: vec![0.0; PARTITION_SIZE],
            buffer_pos: 0,
            partition_index: 0,
            dry_wet: 0.5,
            predelay_samples: 0,
            predelay_buffer_l: vec![0.0; (sample_rate * 0.5) as usize], // Max 500ms predelay
            predelay_buffer_r: vec![0.0; (sample_rate * 0.5) as usize],
            predelay_pos: 0,
            sample_rate,
            ir_loaded: false,
            fft,
            ifft,
            fft_scratch: vec![Complex::new(0.0, 0.0); scratch_len],
        }
    }

    /// Load stereo impulse response
    pub fn load_ir(&mut self, left: &[Sample], right: &[Sample]) {
        let ir_len = left.len().max(right.len());
        let num_partitions = ir_len.div_ceil(PARTITION_SIZE);
        let fft_size = PARTITION_SIZE * 2;

        self.ir_partitions_l.clear();
        self.ir_partitions_r.clear();

        // Partition and FFT the impulse response
        for i in 0..num_partitions {
            let start = i * PARTITION_SIZE;
            let end = (start + PARTITION_SIZE).min(ir_len);

            // Left channel partition
            let mut partition_l = vec![0.0; fft_size];
            for (j, sample) in left.iter().skip(start).take(end - start).enumerate() {
                partition_l[j] = *sample;
            }
            let fft_l = self.fft_forward(&partition_l);
            self.ir_partitions_l.push(fft_l);

            // Right channel partition
            let mut partition_r = vec![0.0; fft_size];
            for (j, sample) in right.iter().skip(start).take(end - start).enumerate() {
                partition_r[j] = *sample;
            }
            let fft_r = self.fft_forward(&partition_r);
            self.ir_partitions_r.push(fft_r);
        }

        self.ir_loaded = !self.ir_partitions_l.is_empty();
        self.reset();
    }

    /// Load mono impulse response (duplicated to stereo)
    pub fn load_ir_mono(&mut self, ir: &[Sample]) {
        self.load_ir(ir, ir);
    }

    /// Set dry/wet mix (0.0 = fully dry, 1.0 = fully wet)
    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    /// Set predelay in milliseconds
    pub fn set_predelay(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.predelay_samples = samples.min(self.predelay_buffer_l.len() - 1);
    }

    /// Forward FFT using rustfft (O(n log n) instead of naive O(n²))
    fn fft_forward(&mut self, input: &[f64]) -> Vec<Complex<f64>> {
        let n = input.len();
        let mut buffer: Vec<Complex<f64>> = input.iter().map(|&x| Complex::new(x, 0.0)).collect();
        buffer.resize(n, Complex::new(0.0, 0.0));

        self.fft
            .process_with_scratch(&mut buffer, &mut self.fft_scratch);
        buffer
    }

    /// Inverse FFT using rustfft (O(n log n))
    fn ifft_inverse(&mut self, input: &[Complex<f64>]) -> Vec<f64> {
        let n = input.len();
        let mut buffer = input.to_vec();

        self.ifft
            .process_with_scratch(&mut buffer, &mut self.fft_scratch);

        // rustfft doesn't normalize, so divide by n
        let scale = 1.0 / n as f64;
        buffer.iter().map(|c| c.re * scale).collect()
    }

    /// Complex multiplication
    #[inline]
    fn complex_mul(a: Complex<f64>, b: Complex<f64>) -> Complex<f64> {
        a * b
    }

    /// Process one partition of convolution
    fn process_partition(&mut self) {
        if !self.ir_loaded {
            return;
        }

        let fft_size = PARTITION_SIZE * 2;

        // Copy buffers to avoid borrow issues
        let input_l: Vec<f64> = self.input_buffer_l.to_vec();
        let input_r: Vec<f64> = self.input_buffer_r.to_vec();

        // FFT the input buffer (now using O(n log n) rustfft)
        let input_fft_l = self.fft_forward(&input_l);
        let input_fft_r = self.fft_forward(&input_r);

        // Accumulate frequency domain multiplication with all partitions
        for i in 0..fft_size {
            self.accum_l[i] = Complex::new(0.0, 0.0);
            self.accum_r[i] = Complex::new(0.0, 0.0);
        }

        let num_partitions = self.ir_partitions_l.len();
        for p in 0..num_partitions {
            let partition_idx = (self.partition_index + num_partitions - p) % num_partitions;

            if partition_idx < self.ir_partitions_l.len() {
                for i in 0..fft_size {
                    let mul_l =
                        Self::complex_mul(input_fft_l[i], self.ir_partitions_l[partition_idx][i]);
                    let mul_r =
                        Self::complex_mul(input_fft_r[i], self.ir_partitions_r[partition_idx][i]);

                    self.accum_l[i] += mul_l;
                    self.accum_r[i] += mul_r;
                }
            }
        }

        // Copy accumulators to avoid borrow issues
        let accum_l_copy = self.accum_l.clone();
        let accum_r_copy = self.accum_r.clone();

        // IFFT back to time domain (now using O(n log n) rustfft)
        let output_l = self.ifft_inverse(&accum_l_copy);
        let output_r = self.ifft_inverse(&accum_r_copy);

        // Overlap-add
        for i in 0..PARTITION_SIZE {
            self.overlap_l[i] += output_l[i];
            self.overlap_r[i] += output_r[i];
        }

        // Save the second half for next overlap
        self.overlap_l[..PARTITION_SIZE]
            .copy_from_slice(&output_l[PARTITION_SIZE..PARTITION_SIZE * 2]);
        self.overlap_r[..PARTITION_SIZE]
            .copy_from_slice(&output_r[PARTITION_SIZE..PARTITION_SIZE * 2]);

        self.partition_index = (self.partition_index + 1) % num_partitions.max(1);
    }
}

impl Clone for ConvolutionReverb {
    fn clone(&self) -> Self {
        // Clone with fresh FFT planners (Arc handles reference counting)
        let fft_size = PARTITION_SIZE * 2;
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);
        let ifft = planner.plan_fft_inverse(fft_size);
        let scratch_len = fft
            .get_inplace_scratch_len()
            .max(ifft.get_inplace_scratch_len());

        Self {
            ir_partitions_l: self.ir_partitions_l.clone(),
            ir_partitions_r: self.ir_partitions_r.clone(),
            input_buffer_l: self.input_buffer_l.clone(),
            input_buffer_r: self.input_buffer_r.clone(),
            accum_l: self.accum_l.clone(),
            accum_r: self.accum_r.clone(),
            overlap_l: self.overlap_l.clone(),
            overlap_r: self.overlap_r.clone(),
            buffer_pos: self.buffer_pos,
            partition_index: self.partition_index,
            dry_wet: self.dry_wet,
            predelay_samples: self.predelay_samples,
            predelay_buffer_l: self.predelay_buffer_l.clone(),
            predelay_buffer_r: self.predelay_buffer_r.clone(),
            predelay_pos: self.predelay_pos,
            sample_rate: self.sample_rate,
            ir_loaded: self.ir_loaded,
            fft,
            ifft,
            fft_scratch: vec![Complex::new(0.0, 0.0); scratch_len],
        }
    }
}

impl std::fmt::Debug for ConvolutionReverb {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConvolutionReverb")
            .field("sample_rate", &self.sample_rate)
            .field("ir_loaded", &self.ir_loaded)
            .field("dry_wet", &self.dry_wet)
            .field("predelay_samples", &self.predelay_samples)
            .field("partition_count", &self.ir_partitions_l.len())
            .finish()
    }
}

impl Processor for ConvolutionReverb {
    fn reset(&mut self) {
        let fft_size = PARTITION_SIZE * 2;

        self.input_buffer_l.fill(0.0);
        self.input_buffer_r.fill(0.0);
        self.accum_l = vec![Complex::new(0.0, 0.0); fft_size];
        self.accum_r = vec![Complex::new(0.0, 0.0); fft_size];
        self.overlap_l.fill(0.0);
        self.overlap_r.fill(0.0);
        self.predelay_buffer_l.fill(0.0);
        self.predelay_buffer_r.fill(0.0);
        self.buffer_pos = 0;
        self.partition_index = 0;
        self.predelay_pos = 0;
    }

    fn latency(&self) -> usize {
        PARTITION_SIZE + self.predelay_samples
    }
}

impl StereoProcessor for ConvolutionReverb {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if !self.ir_loaded {
            return (left, right);
        }

        // Apply predelay
        let delayed_l = self.predelay_buffer_l[self.predelay_pos];
        let delayed_r = self.predelay_buffer_r[self.predelay_pos];
        self.predelay_buffer_l[self.predelay_pos] = left;
        self.predelay_buffer_r[self.predelay_pos] = right;
        self.predelay_pos = (self.predelay_pos + 1) % self.predelay_buffer_l.len().max(1);

        // Add to input buffer
        self.input_buffer_l[self.buffer_pos] = delayed_l;
        self.input_buffer_r[self.buffer_pos] = delayed_r;

        // Get wet signal from overlap buffer
        let wet_l = self.overlap_l[self.buffer_pos % PARTITION_SIZE];
        let wet_r = self.overlap_r[self.buffer_pos % PARTITION_SIZE];

        self.buffer_pos += 1;

        // Process partition when buffer is full
        if self.buffer_pos >= PARTITION_SIZE {
            self.process_partition();

            // Shift input buffer
            for i in 0..PARTITION_SIZE {
                self.input_buffer_l[i] = self.input_buffer_l[PARTITION_SIZE + i];
                self.input_buffer_r[i] = self.input_buffer_r[PARTITION_SIZE + i];
            }
            self.buffer_pos = PARTITION_SIZE;
        }

        // Mix dry and wet
        let out_l = left * (1.0 - self.dry_wet) + wet_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + wet_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for ConvolutionReverb {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.predelay_buffer_l = vec![0.0; (sample_rate * 0.5) as usize];
        self.predelay_buffer_r = vec![0.0; (sample_rate * 0.5) as usize];
    }
}

/// Algorithmic reverb type
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ReverbType {
    #[default]
    Room,
    Hall,
    Plate,
    Chamber,
    Spring,
}

/// Allpass filter for diffusion
#[derive(Debug, Clone)]
struct AllpassFilter {
    buffer: Vec<Sample>,
    pos: usize,
    feedback: f64,
}

impl AllpassFilter {
    fn new(delay_samples: usize, feedback: f64) -> Self {
        Self {
            buffer: vec![0.0; delay_samples.max(1)],
            pos: 0,
            feedback,
        }
    }

    #[inline]
    fn process(&mut self, input: Sample) -> Sample {
        let delayed = self.buffer[self.pos];
        let output = delayed - input * self.feedback;
        self.buffer[self.pos] = input + delayed * self.feedback;
        self.pos = (self.pos + 1) % self.buffer.len();
        output
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.pos = 0;
    }
}

/// Comb filter for resonance
#[derive(Debug, Clone)]
struct CombFilter {
    buffer: Vec<Sample>,
    pos: usize,
    feedback: f64,
    damping: f64,
    filter_state: f64,
}

impl CombFilter {
    fn new(delay_samples: usize, feedback: f64, damping: f64) -> Self {
        Self {
            buffer: vec![0.0; delay_samples.max(1)],
            pos: 0,
            feedback,
            damping,
            filter_state: 0.0,
        }
    }

    #[inline]
    fn process(&mut self, input: Sample) -> Sample {
        let delayed = self.buffer[self.pos];

        // One-pole lowpass for damping
        self.filter_state = delayed * (1.0 - self.damping) + self.filter_state * self.damping;

        self.buffer[self.pos] = input + self.filter_state * self.feedback;
        self.pos = (self.pos + 1) % self.buffer.len();

        delayed
    }

    fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback;
    }

    fn set_damping(&mut self, damping: f64) {
        self.damping = damping;
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.pos = 0;
        self.filter_state = 0.0;
    }
}

/// Algorithmic stereo reverb (Freeverb-inspired)
#[derive(Debug, Clone)]
pub struct AlgorithmicReverb {
    reverb_type: ReverbType,

    // Comb filters (parallel, for each channel)
    combs_l: Vec<CombFilter>,
    combs_r: Vec<CombFilter>,

    // Allpass filters (series, for diffusion)
    allpasses_l: Vec<AllpassFilter>,
    allpasses_r: Vec<AllpassFilter>,

    // Parameters
    room_size: f64,
    damping: f64,
    width: f64,
    dry_wet: f64,
    predelay_ms: f64,

    // Predelay
    predelay_buffer_l: Vec<Sample>,
    predelay_buffer_r: Vec<Sample>,
    predelay_pos: usize,
    predelay_samples: usize,

    sample_rate: f64,
}

impl AlgorithmicReverb {
    // Comb filter delay times in samples at 44.1kHz (Freeverb values)
    const COMB_TUNINGS: [usize; 8] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    const ALLPASS_TUNINGS: [usize; 4] = [556, 441, 341, 225];
    const STEREO_SPREAD: usize = 23;

    pub fn new(sample_rate: f64) -> Self {
        let scale = sample_rate / 44100.0;

        let combs_l: Vec<_> = Self::COMB_TUNINGS
            .iter()
            .map(|&t| CombFilter::new((t as f64 * scale) as usize, 0.84, 0.2))
            .collect();

        let combs_r: Vec<_> = Self::COMB_TUNINGS
            .iter()
            .map(|&t| {
                CombFilter::new(
                    ((t + Self::STEREO_SPREAD) as f64 * scale) as usize,
                    0.84,
                    0.2,
                )
            })
            .collect();

        let allpasses_l: Vec<_> = Self::ALLPASS_TUNINGS
            .iter()
            .map(|&t| AllpassFilter::new((t as f64 * scale) as usize, 0.5))
            .collect();

        let allpasses_r: Vec<_> = Self::ALLPASS_TUNINGS
            .iter()
            .map(|&t| AllpassFilter::new(((t + Self::STEREO_SPREAD) as f64 * scale) as usize, 0.5))
            .collect();

        let max_predelay = (sample_rate * 0.2) as usize; // Max 200ms predelay

        Self {
            reverb_type: ReverbType::Room,
            combs_l,
            combs_r,
            allpasses_l,
            allpasses_r,
            room_size: 0.5,
            damping: 0.5,
            width: 1.0,
            dry_wet: 0.3,
            predelay_ms: 0.0,
            predelay_buffer_l: vec![0.0; max_predelay],
            predelay_buffer_r: vec![0.0; max_predelay],
            predelay_pos: 0,
            predelay_samples: 0,
            sample_rate,
        }
    }

    pub fn set_type(&mut self, reverb_type: ReverbType) {
        self.reverb_type = reverb_type;

        // Adjust parameters based on type
        match reverb_type {
            ReverbType::Room => {
                self.set_room_size(0.4);
                self.set_damping(0.5);
            }
            ReverbType::Hall => {
                self.set_room_size(0.8);
                self.set_damping(0.3);
            }
            ReverbType::Plate => {
                self.set_room_size(0.6);
                self.set_damping(0.1);
            }
            ReverbType::Chamber => {
                self.set_room_size(0.5);
                self.set_damping(0.4);
            }
            ReverbType::Spring => {
                self.set_room_size(0.3);
                self.set_damping(0.7);
            }
        }
    }

    pub fn set_room_size(&mut self, size: f64) {
        self.room_size = size.clamp(0.0, 1.0);

        // Freeverb feedback calculation
        let feedback = 0.28 + self.room_size * 0.7;

        for comb in &mut self.combs_l {
            comb.set_feedback(feedback);
        }
        for comb in &mut self.combs_r {
            comb.set_feedback(feedback);
        }
    }

    pub fn set_damping(&mut self, damping: f64) {
        self.damping = damping.clamp(0.0, 1.0);

        for comb in &mut self.combs_l {
            comb.set_damping(self.damping);
        }
        for comb in &mut self.combs_r {
            comb.set_damping(self.damping);
        }
    }

    pub fn set_width(&mut self, width: f64) {
        self.width = width.clamp(0.0, 1.0);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    pub fn set_predelay(&mut self, ms: f64) {
        self.predelay_ms = ms.clamp(0.0, 200.0);
        self.predelay_samples =
            ((ms * 0.001 * self.sample_rate) as usize).min(self.predelay_buffer_l.len() - 1);
    }
}

impl Processor for AlgorithmicReverb {
    fn reset(&mut self) {
        for comb in &mut self.combs_l {
            comb.reset();
        }
        for comb in &mut self.combs_r {
            comb.reset();
        }
        for ap in &mut self.allpasses_l {
            ap.reset();
        }
        for ap in &mut self.allpasses_r {
            ap.reset();
        }
        self.predelay_buffer_l.fill(0.0);
        self.predelay_buffer_r.fill(0.0);
        self.predelay_pos = 0;
    }

    fn latency(&self) -> usize {
        self.predelay_samples
    }
}

impl StereoProcessor for AlgorithmicReverb {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Apply predelay
        let predelay_read_pos = (self.predelay_pos + self.predelay_buffer_l.len()
            - self.predelay_samples)
            % self.predelay_buffer_l.len();

        let delayed_l = self.predelay_buffer_l[predelay_read_pos];
        let delayed_r = self.predelay_buffer_r[predelay_read_pos];

        self.predelay_buffer_l[self.predelay_pos] = left;
        self.predelay_buffer_r[self.predelay_pos] = right;
        self.predelay_pos = (self.predelay_pos + 1) % self.predelay_buffer_l.len();

        // Sum input to mono for reverb
        let input = (delayed_l + delayed_r) * 0.5;

        // Parallel comb filters
        let mut comb_out_l = 0.0;
        let mut comb_out_r = 0.0;

        for comb in &mut self.combs_l {
            comb_out_l += comb.process(input);
        }
        for comb in &mut self.combs_r {
            comb_out_r += comb.process(input);
        }

        // Scale comb output
        comb_out_l /= self.combs_l.len() as f64;
        comb_out_r /= self.combs_r.len() as f64;

        // Series allpass filters for diffusion
        let mut ap_out_l = comb_out_l;
        let mut ap_out_r = comb_out_r;

        for ap in &mut self.allpasses_l {
            ap_out_l = ap.process(ap_out_l);
        }
        for ap in &mut self.allpasses_r {
            ap_out_r = ap.process(ap_out_r);
        }

        // Stereo width processing
        let wet_l = ap_out_l * self.width + ap_out_r * (1.0 - self.width);
        let wet_r = ap_out_r * self.width + ap_out_l * (1.0 - self.width);

        // Mix dry and wet
        let out_l = left * (1.0 - self.dry_wet) + wet_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + wet_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for AlgorithmicReverb {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        if (sample_rate - self.sample_rate).abs() > 1.0 {
            // Recreate filters for new sample rate
            *self = Self::new(sample_rate);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_algorithmic_reverb() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_room_size(0.5);
        reverb.set_dry_wet(0.3);

        // Process impulse
        let (l, r) = reverb.process_sample(1.0, 1.0);

        // Should have some output
        assert!(l.abs() > 0.0 || r.abs() > 0.0);

        // Process silence - reverb tail should decay
        for _ in 0..10000 {
            let _ = reverb.process_sample(0.0, 0.0);
        }
    }

    #[test]
    fn test_convolution_reverb_without_ir() {
        let mut reverb = ConvolutionReverb::new(48000.0);

        // Without IR, should pass through
        let (l, r) = reverb.process_sample(0.5, 0.5);
        assert!((l - 0.5).abs() < 1e-10);
        assert!((r - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_reverb_types() {
        let mut reverb = AlgorithmicReverb::new(48000.0);

        for reverb_type in [ReverbType::Room, ReverbType::Hall, ReverbType::Plate] {
            reverb.set_type(reverb_type);

            // Process some samples
            for _ in 0..1000 {
                let _ = reverb.process_sample(0.5, 0.5);
            }
        }
    }
}
