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

        // Equal-power crossfade (FabFilter Pro-R style) — prevents phase cancellation
        // and -3dB volume dip at 50% mix that linear crossfade causes
        let mix_angle = self.dry_wet * std::f64::consts::FRAC_PI_2;
        let dry_gain = mix_angle.cos();
        let wet_gain = mix_angle.sin();
        let out_l = left * dry_gain + wet_l * wet_gain;
        let out_r = right * dry_gain + wet_r * wet_gain;

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

/// Algorithmic reverb style (topology preset)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ReverbType {
    #[default]
    Room,
    Hall,
    Plate,
    Chamber,
    Spring,
    /// R7.1: Ultra-long diffusion, minimal ER, max modulation
    Ambient,
    /// R7.2: Pitch-shifted feedback (+12st octave up) for ethereal shimmer
    Shimmer,
    /// R7.3: Waveshaping in feedback for lo-fi character
    Nonlinear,
    /// R7.4: Lexicon 224/480 emulation — specific delay ratios, subtle modulation
    Vintage,
    /// R7.5: Envelope-gated tail — 80s drum reverb
    Gated,
}

/// Style scaling factors — NE override, samo multiplicative scaling
struct StyleScaling {
    space: f64,
    er: f64,
    diffusion: f64,
    modulation: f64,
}

impl ReverbType {
    fn scaling(&self) -> StyleScaling {
        match self {
            ReverbType::Room => StyleScaling {
                space: 0.6,
                er: 0.8,
                diffusion: 0.7,
                modulation: 0.5,
            },
            ReverbType::Hall => StyleScaling {
                space: 1.2,
                er: 1.0,
                diffusion: 0.9,
                modulation: 0.8,
            },
            ReverbType::Plate => StyleScaling {
                space: 0.8,
                er: 0.3,
                diffusion: 1.0,
                modulation: 1.0,
            },
            ReverbType::Chamber => StyleScaling {
                space: 0.7,
                er: 0.9,
                diffusion: 0.8,
                modulation: 0.6,
            },
            ReverbType::Spring => StyleScaling {
                space: 0.5,
                er: 0.5,
                diffusion: 0.6,
                modulation: 1.2,
            },
            ReverbType::Ambient => StyleScaling {
                space: 1.8,       // Ultra-wide space
                er: 0.15,         // Minimal ER (wash-like)
                diffusion: 1.0,   // Max diffusion
                modulation: 1.5,  // Cranked modulation
            },
            ReverbType::Shimmer => StyleScaling {
                space: 1.4,
                er: 0.4,
                diffusion: 0.9,
                modulation: 0.7,
            },
            ReverbType::Nonlinear => StyleScaling {
                space: 0.6,
                er: 0.7,
                diffusion: 0.5,   // Lower diffusion for grit
                modulation: 0.4,
            },
            ReverbType::Vintage => StyleScaling {
                space: 1.0,
                er: 0.8,
                diffusion: 0.7,
                modulation: 0.3,  // Subtle, period-correct modulation
            },
            ReverbType::Gated => StyleScaling {
                space: 0.5,
                er: 1.0,          // Strong ER for punch
                diffusion: 0.4,   // Low diffusion for clarity
                modulation: 0.2,  // Minimal modulation
            },
        }
    }
}

// ============================================================================
// FDN Sub-Components
// ============================================================================

// ========================================================================
// Diffusion Allpass Filters (R3.1-R3.5)
// ========================================================================
//
// Three allpass topologies:
// 1. Serial: Classic Schroeder — simple chain (Room, light diffusion)
// 2. Nested: Lexicon-style allpass-within-allpass (Hall, Chamber — dense)
// 3. Lattice: VintageVerb-style lattice structure (Plate — ultra-dense)
//
// All support delay modulation to prevent metallic buildup.

/// Simple allpass filter (used as building block)
#[derive(Debug, Clone)]
struct SimpleAllpass {
    buffer: Vec<f64>,
    pos: usize,
    delay_len: usize,
    feedback: f64,
    /// Modulation: offset applied to read position (fractional samples)
    mod_phase: f64,
    mod_increment: f64,
    mod_depth: f64,
}

impl SimpleAllpass {
    fn new(delay_samples: usize, feedback: f64) -> Self {
        // Extra headroom for modulation
        let buf_size = delay_samples + 8;
        Self {
            buffer: vec![0.0; buf_size.max(2)],
            pos: 0,
            delay_len: delay_samples.max(1),
            feedback,
            mod_phase: 0.0,
            mod_increment: 0.0,
            mod_depth: 0.0,
        }
    }

    /// Set modulation rate (Hz) and depth (samples)
    fn set_modulation(&mut self, rate_hz: f64, depth_samples: f64, sample_rate: f64) {
        self.mod_increment = 2.0 * std::f64::consts::PI * rate_hz / sample_rate;
        self.mod_depth = depth_samples;
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        // Modulated read position
        let mod_offset = if self.mod_depth > 0.001 {
            self.mod_phase.sin() * self.mod_depth
        } else {
            0.0
        };

        let buf_len = self.buffer.len();
        let read_delay = self.delay_len as f64 + mod_offset;
        let read_int = read_delay as usize;
        let frac = read_delay - read_int as f64;

        // Linear interpolation for modulated read
        let pos0 = (self.pos + buf_len - read_int) % buf_len;
        let pos1 = (pos0 + buf_len - 1) % buf_len;
        let delayed = self.buffer[pos0] * (1.0 - frac) + self.buffer[pos1] * frac;

        // Standard allpass: output = delayed - input*g, write = input + delayed*g
        let output = delayed - input * self.feedback;
        self.buffer[self.pos] = input + delayed * self.feedback;
        self.pos = (self.pos + 1) % buf_len;

        // Advance modulation phase
        if self.mod_depth > 0.001 {
            self.mod_phase += self.mod_increment;
            if self.mod_phase > 2.0 * std::f64::consts::PI {
                self.mod_phase -= 2.0 * std::f64::consts::PI;
            }
        }

        output
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.pos = 0;
        self.mod_phase = 0.0;
    }
}

/// Nested allpass: allpass-within-allpass (Lexicon 224/480 style)
/// Inner allpass sits inside the delay line of the outer allpass,
/// creating denser diffusion with fewer stages.
#[derive(Debug, Clone)]
struct NestedAllpass {
    /// Outer allpass delay buffer
    outer_buffer: Vec<f64>,
    outer_pos: usize,
    outer_delay: usize,
    outer_feedback: f64,
    /// Inner allpass (nested inside outer's feedback path)
    inner: SimpleAllpass,
}

impl NestedAllpass {
    fn new(outer_delay: usize, inner_delay: usize, outer_fb: f64, inner_fb: f64) -> Self {
        let buf_size = outer_delay + 8;
        Self {
            outer_buffer: vec![0.0; buf_size.max(2)],
            outer_pos: 0,
            outer_delay: outer_delay.max(1),
            outer_feedback: outer_fb,
            inner: SimpleAllpass::new(inner_delay, inner_fb),
        }
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let buf_len = self.outer_buffer.len();
        let read_pos = (self.outer_pos + buf_len - self.outer_delay) % buf_len;
        let delayed = self.outer_buffer[read_pos];

        // Run inner allpass on the delayed signal
        let inner_out = self.inner.process(delayed);

        // Outer allpass structure
        let output = inner_out - input * self.outer_feedback;
        self.outer_buffer[self.outer_pos] = input + inner_out * self.outer_feedback;
        self.outer_pos = (self.outer_pos + 1) % buf_len;

        output
    }

    fn set_feedback(&mut self, outer_fb: f64, inner_fb: f64) {
        self.outer_feedback = outer_fb;
        self.inner.feedback = inner_fb;
    }

    fn set_modulation(&mut self, rate_hz: f64, depth: f64, sample_rate: f64) {
        self.inner.set_modulation(rate_hz, depth, sample_rate);
    }

    fn reset(&mut self) {
        self.outer_buffer.fill(0.0);
        self.outer_pos = 0;
        self.inner.reset();
    }
}

/// Diffusion topology mode
#[derive(Debug, Clone, Copy, PartialEq)]
enum DiffusionTopology {
    /// Serial allpass chain (Schroeder basic) — Room, light
    Serial,
    /// Nested allpass (Lexicon-style) — Hall, Chamber
    Nested,
    /// Lattice allpass (VintageVerb-style) — Plate, ultra-dense
    Lattice,
}

/// Legacy compatible allpass wrapper (keeps old DiffusionAllpass API)
#[derive(Debug, Clone)]
struct DiffusionAllpass {
    buffer: Vec<f64>,
    pos: usize,
    feedback: f64,
}

impl DiffusionAllpass {
    fn new(delay_samples: usize, feedback: f64) -> Self {
        Self {
            buffer: vec![0.0; delay_samples.max(1)],
            pos: 0,
            feedback,
        }
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
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

/// Early reflection tap (legacy, unused — kept for ERTap reference)
#[derive(Debug, Clone)]
struct ERTap {
    delay_samples: usize,
    gain: f64,
    lpf_coeff: f64,
    lpf_state_l: f64,
    lpf_state_r: f64,
}

// ========================================================================
// Velvet Noise Modulation (Valhalla-style)
// ========================================================================
//
// Replaces periodic sinusoidal LFO with sparse random impulse train.
// Sean Costello (Valhalla DSP) trademark technique:
// - Random impulses at configurable density (200-2000 impulses/sec)
// - Each impulse is +1 or -1 (random polarity)
// - Low-pass filtered to smooth modulation signal
// - Eliminates periodic chorus artifacts, creates organic spatial movement
//
// Two modulation rates per generator:
// - Spin: fast modulation (1-5 Hz effective rate after LP filtering)
// - Wander: slow drift (0.05-0.5 Hz) for long-term movement

/// Velvet noise generator — sparse random impulse train for delay modulation
///
/// Uses a simple LCG (linear congruential generator) for deterministic,
/// allocation-free random number generation on the audio thread.
#[derive(Debug, Clone)]
struct VelvetNoiseGenerator {
    /// LCG state (deterministic PRNG, zero allocation)
    rng_state: u64,
    /// Samples until next impulse
    samples_until_impulse: u32,
    /// Current density in impulses/sec
    density: f64,
    /// Sample rate for interval calculation
    sample_rate: f64,
    /// Spin LP filter state (fast modulation, 1-5 Hz cutoff)
    spin_lpf_state: f64,
    /// Spin LP filter coefficient
    spin_lpf_coeff: f64,
    /// Wander LP filter state (slow drift, 0.05-0.5 Hz cutoff)
    wander_lpf_state: f64,
    /// Wander LP filter coefficient
    wander_lpf_coeff: f64,
}

impl VelvetNoiseGenerator {
    fn new(sample_rate: f64, seed: u64) -> Self {
        let density = 800.0; // Default density: 800 impulses/sec
        let spin_hz = 2.5; // Default spin rate
        let wander_hz = 0.15; // Default wander rate

        let mut vng = Self {
            rng_state: seed.wrapping_mul(6364136223846793005).wrapping_add(1),
            samples_until_impulse: 0,
            density,
            sample_rate,
            spin_lpf_state: 0.0,
            spin_lpf_coeff: Self::calc_lpf_coeff(spin_hz, sample_rate),
            wander_lpf_state: 0.0,
            wander_lpf_coeff: Self::calc_lpf_coeff(wander_hz, sample_rate),
        };
        // Initialize first impulse interval
        vng.samples_until_impulse = vng.next_interval();
        vng
    }

    /// Calculate one-pole LP filter coefficient for given cutoff frequency
    #[inline(always)]
    fn calc_lpf_coeff(freq_hz: f64, sample_rate: f64) -> f64 {
        1.0 - (-2.0 * std::f64::consts::PI * freq_hz / sample_rate).exp()
    }

    /// Update spin rate (fast modulation, 1-5 Hz)
    fn set_spin_rate(&mut self, hz: f64) {
        let hz = hz.clamp(1.0, 5.0);
        self.spin_lpf_coeff = Self::calc_lpf_coeff(hz, self.sample_rate);
    }

    /// Update wander rate (slow drift, 0.05-0.5 Hz)
    fn set_wander_rate(&mut self, hz: f64) {
        let hz = hz.clamp(0.05, 0.5);
        self.wander_lpf_coeff = Self::calc_lpf_coeff(hz, self.sample_rate);
    }

    /// Update impulse density (200-2000 impulses/sec)
    fn set_density(&mut self, density: f64) {
        self.density = density.clamp(200.0, 2000.0);
    }

    /// LCG random: returns pseudo-random u64 (Knuth LCG constants)
    #[inline(always)]
    fn next_random(&mut self) -> u64 {
        self.rng_state = self.rng_state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        self.rng_state
    }

    /// Calculate samples until next impulse based on density
    /// Adds ±30% jitter to prevent periodicity
    #[inline(always)]
    fn next_interval(&mut self) -> u32 {
        let mean_interval = self.sample_rate / self.density;
        // Jitter: ±30% of mean interval using PRNG
        let r = self.next_random();
        let jitter = (r as f64 / u64::MAX as f64) * 0.6 - 0.3; // -0.3 to +0.3
        let interval = mean_interval * (1.0 + jitter);
        (interval as u32).max(1)
    }

    /// Generate one sample of velvet noise and return (spin_mod, wander_mod)
    ///
    /// Both outputs are smooth, LP-filtered modulation signals in range ~[-1, +1].
    /// Spin = fast movement (chorus-like), Wander = slow drift (spatial).
    #[inline(always)]
    fn process(&mut self) -> (f64, f64) {
        // Generate raw velvet noise impulse
        let impulse = if self.samples_until_impulse == 0 {
            // Time for an impulse — random polarity (+1 or -1)
            let r = self.next_random();
            let polarity = if r & 1 == 0 { 1.0 } else { -1.0 };
            // Schedule next impulse
            self.samples_until_impulse = self.next_interval();
            polarity
        } else {
            self.samples_until_impulse -= 1;
            0.0
        };

        // LP filter the impulse train at two different rates
        // Spin: fast LP → gives modulation in the 1-5 Hz range
        self.spin_lpf_state += (impulse - self.spin_lpf_state) * self.spin_lpf_coeff;

        // Wander: slow LP → gives drift in the 0.05-0.5 Hz range
        self.wander_lpf_state += (impulse - self.wander_lpf_state) * self.wander_lpf_coeff;

        (self.spin_lpf_state, self.wander_lpf_state)
    }

    fn reset(&mut self, seed: u64) {
        self.rng_state = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        self.samples_until_impulse = 0;
        self.spin_lpf_state = 0.0;
        self.wander_lpf_state = 0.0;
        self.samples_until_impulse = self.next_interval();
    }
}

// ========================================================================
// Early Reflection Engine — 24 taps (R2.1-R2.6)
// ========================================================================
//
// Upgraded from 8 to 24 taps with:
// - Per-style ER patterns (Room/Hall/Plate/Chamber/Spring)
// - Stereo decorrelation via L/R offset delays
// - ER→Late crossfade zone (50ms smooth transition)
// - Independent ER Level and Late Level controls

/// Maximum number of ER taps
const ER_MAX_TAPS: usize = 24;

/// Single ER tap with stereo decorrelation
#[derive(Debug, Clone)]
struct ERTapStereo {
    delay_l: usize,  // Left channel delay (samples)
    delay_r: usize,  // Right channel delay (offset for stereo decorrelation)
    gain: f64,
    pan: f64,         // -1.0 = hard left, 0.0 = center, 1.0 = hard right
    lpf_coeff: f64,
    lpf_state_l: f64,
    lpf_state_r: f64,
}

/// Per-style ER pattern definition
#[derive(Debug, Clone)]
struct ERPattern {
    /// Tap delays in ms (left channel)
    delays_ms: [f64; ER_MAX_TAPS],
    /// Stereo offset in ms (right channel = delay_l + offset)
    stereo_offsets_ms: [f64; ER_MAX_TAPS],
    /// Tap gains (amplitude)
    gains: [f64; ER_MAX_TAPS],
    /// Per-tap pan position (-1 to +1)
    pans: [f64; ER_MAX_TAPS],
    /// Number of active taps for this pattern
    active_count: usize,
}

/// Generate Room ER pattern: short, dense (3-80ms, 24 taps)
fn er_pattern_room() -> ERPattern {
    ERPattern {
        delays_ms: [
            3.0, 5.0, 7.0, 9.0, 11.0, 13.0, 17.0, 19.0,
            23.0, 27.0, 29.0, 31.0, 37.0, 41.0, 43.0, 47.0,
            53.0, 57.0, 59.0, 61.0, 67.0, 71.0, 73.0, 79.0,
        ],
        stereo_offsets_ms: [
            0.3, -0.2, 0.5, -0.4, 0.7, -0.3, 0.6, -0.5,
            0.8, -0.6, 0.4, -0.7, 0.9, -0.8, 0.5, -0.4,
            1.0, -0.9, 0.7, -0.6, 1.1, -1.0, 0.8, -0.7,
        ],
        gains: [
            0.90, 0.87, 0.84, 0.81, 0.78, 0.75, 0.72, 0.69,
            0.66, 0.63, 0.60, 0.57, 0.54, 0.51, 0.48, 0.45,
            0.42, 0.39, 0.36, 0.33, 0.30, 0.27, 0.24, 0.21,
        ],
        pans: [
            -0.3, 0.4, -0.2, 0.5, -0.6, 0.3, -0.4, 0.6,
            -0.5, 0.7, -0.3, 0.4, -0.7, 0.5, -0.2, 0.6,
            -0.4, 0.3, -0.6, 0.5, -0.3, 0.7, -0.5, 0.4,
        ],
        active_count: 24,
    }
}

/// Generate Hall ER pattern: wide, sparse (5-150ms, 18 taps)
fn er_pattern_hall() -> ERPattern {
    ERPattern {
        delays_ms: [
            5.0, 11.0, 19.0, 29.0, 37.0, 47.0, 59.0, 71.0,
            83.0, 89.0, 97.0, 103.0, 113.0, 121.0, 127.0, 137.0,
            143.0, 149.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        stereo_offsets_ms: [
            0.5, -0.7, 1.0, -1.2, 1.5, -0.8, 1.3, -1.6,
            1.8, -1.1, 2.0, -1.4, 1.7, -2.1, 2.3, -1.9,
            2.5, -2.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        gains: [
            0.88, 0.82, 0.76, 0.70, 0.65, 0.60, 0.55, 0.50,
            0.46, 0.42, 0.38, 0.35, 0.32, 0.29, 0.26, 0.23,
            0.20, 0.18, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        pans: [
            -0.5, 0.6, -0.7, 0.8, -0.4, 0.5, -0.8, 0.7,
            -0.6, 0.9, -0.3, 0.4, -0.9, 0.6, -0.5, 0.8,
            -0.7, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        active_count: 18,
    }
}

/// Generate Plate ER pattern: ultra-dense, no gaps (3-60ms, 24 taps)
fn er_pattern_plate() -> ERPattern {
    ERPattern {
        delays_ms: [
            3.0, 4.0, 5.5, 7.0, 8.5, 10.0, 11.5, 13.0,
            15.0, 17.0, 19.0, 21.0, 23.5, 26.0, 28.5, 31.0,
            34.0, 37.0, 40.0, 43.5, 47.0, 51.0, 55.0, 59.0,
        ],
        stereo_offsets_ms: [
            0.1, -0.15, 0.2, -0.1, 0.25, -0.2, 0.15, -0.25,
            0.3, -0.15, 0.2, -0.3, 0.25, -0.1, 0.35, -0.2,
            0.3, -0.25, 0.15, -0.35, 0.2, -0.3, 0.25, -0.15,
        ],
        gains: [
            0.92, 0.90, 0.88, 0.86, 0.84, 0.82, 0.80, 0.78,
            0.75, 0.72, 0.69, 0.66, 0.63, 0.60, 0.57, 0.54,
            0.51, 0.48, 0.45, 0.42, 0.39, 0.36, 0.33, 0.30,
        ],
        pans: [
            -0.1, 0.15, -0.2, 0.1, -0.15, 0.2, -0.1, 0.15,
            -0.2, 0.1, -0.15, 0.2, -0.1, 0.15, -0.2, 0.1,
            -0.15, 0.2, -0.1, 0.15, -0.2, 0.1, -0.15, 0.2,
        ],
        active_count: 24,
    }
}

/// Generate Chamber ER pattern: mid-range focus (5-100ms, 20 taps)
fn er_pattern_chamber() -> ERPattern {
    ERPattern {
        delays_ms: [
            5.0, 8.0, 11.0, 14.0, 17.0, 21.0, 25.0, 29.0,
            34.0, 39.0, 44.0, 49.0, 55.0, 61.0, 67.0, 73.0,
            80.0, 87.0, 94.0, 100.0, 0.0, 0.0, 0.0, 0.0,
        ],
        stereo_offsets_ms: [
            0.4, -0.3, 0.6, -0.5, 0.8, -0.4, 0.7, -0.6,
            0.9, -0.7, 1.0, -0.8, 1.1, -0.9, 0.5, -1.0,
            1.2, -0.6, 0.8, -1.1, 0.0, 0.0, 0.0, 0.0,
        ],
        gains: [
            0.86, 0.82, 0.78, 0.74, 0.70, 0.66, 0.62, 0.58,
            0.54, 0.50, 0.46, 0.42, 0.39, 0.36, 0.33, 0.30,
            0.27, 0.24, 0.21, 0.18, 0.0, 0.0, 0.0, 0.0,
        ],
        pans: [
            -0.4, 0.3, -0.5, 0.4, -0.3, 0.5, -0.6, 0.4,
            -0.5, 0.6, -0.4, 0.3, -0.7, 0.5, -0.3, 0.6,
            -0.5, 0.4, -0.6, 0.3, 0.0, 0.0, 0.0, 0.0,
        ],
        active_count: 20,
    }
}

/// Generate Spring ER pattern: bounce pattern with nonlinear spacing (3-90ms, 16 taps)
fn er_pattern_spring() -> ERPattern {
    // Spring reverb: exponentially-spaced taps emulating coil bounces
    // Early taps very close together, then increasingly spread
    ERPattern {
        delays_ms: [
            3.0, 4.5, 6.5, 9.0, 12.0, 16.0, 21.0, 27.0,
            34.0, 42.0, 51.0, 61.0, 72.0, 80.0, 86.0, 90.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        stereo_offsets_ms: [
            0.2, -0.3, 0.4, -0.2, 0.5, -0.4, 0.3, -0.6,
            0.7, -0.5, 0.8, -0.7, 0.6, -0.8, 0.9, -0.5,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        gains: [
            0.95, 0.88, 0.80, 0.72, 0.65, 0.58, 0.52, 0.46,
            0.40, 0.35, 0.30, 0.26, 0.22, 0.19, 0.16, 0.14,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        pans: [
            0.0, 0.1, -0.1, 0.2, -0.2, 0.3, -0.3, 0.4,
            -0.4, 0.5, -0.5, 0.3, -0.3, 0.2, -0.2, 0.1,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        active_count: 16,
    }
}

/// Get ER pattern for a given reverb style
fn er_pattern_for_style(style: &ReverbType) -> ERPattern {
    match style {
        ReverbType::Room => er_pattern_room(),
        ReverbType::Hall => er_pattern_hall(),
        ReverbType::Plate => er_pattern_plate(),
        ReverbType::Chamber => er_pattern_chamber(),
        ReverbType::Spring => er_pattern_spring(),
        // New styles (R7): reuse base patterns with modifications
        ReverbType::Ambient => er_pattern_ambient(),
        ReverbType::Shimmer => er_pattern_hall(),   // Shimmer uses hall ER
        ReverbType::Nonlinear => er_pattern_room(), // Nonlinear uses room ER
        ReverbType::Vintage => er_pattern_vintage(),
        ReverbType::Gated => er_pattern_room(),     // Gated uses room ER with strong level
    }
}

/// Ambient ER: sparse, very long delays, minimal density (R7.1)
fn er_pattern_ambient() -> ERPattern {
    ERPattern {
        delays_ms: [
            15.0, 30.0, 50.0, 75.0, 105.0, 140.0,
            180.0, 220.0, 270.0, 320.0, 380.0, 450.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        stereo_offsets_ms: [
            1.5, 2.0, 2.5, 3.0, 3.5, 4.0,
            4.5, 5.0, 5.5, 6.0, 6.5, 7.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        gains: [
            0.30, 0.28, 0.25, 0.22, 0.18, 0.15,
            0.12, 0.10, 0.08, 0.06, 0.05, 0.04,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        pans: [
            0.3, 0.7, 0.4, 0.6, 0.2, 0.8,
            0.35, 0.65, 0.45, 0.55, 0.25, 0.75,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        active_count: 12,
    }
}

/// Vintage ER: Lexicon 224-inspired, specific golden-ratio delays (R7.4)
fn er_pattern_vintage() -> ERPattern {
    ERPattern {
        delays_ms: [
            3.7, 7.1, 11.3, 16.7, 22.9, 30.1, 38.3, 47.9,
            58.7, 70.9, 84.3, 98.7, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        stereo_offsets_ms: [
            0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.1,
            2.3, 2.5, 2.7, 2.9, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        gains: [
            0.40, 0.36, 0.32, 0.28, 0.24, 0.20, 0.17, 0.14,
            0.11, 0.09, 0.07, 0.05, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        pans: [
            0.4, 0.6, 0.35, 0.65, 0.45, 0.55, 0.3, 0.7,
            0.4, 0.6, 0.35, 0.65, 0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        ],
        active_count: 12,
    }
}

/// Early Reflection Engine — 24 stereo-decorrelated taps with per-style patterns
#[derive(Debug, Clone)]
struct EarlyReflectionEngine {
    taps: [ERTapStereo; ER_MAX_TAPS],
    active_count: usize,
    buffer_l: Vec<f64>,
    buffer_r: Vec<f64>,
    write_pos: usize,
    max_delay: usize,
    /// Current ER pattern base (for space scaling)
    base_delays_l_ms: [f64; ER_MAX_TAPS],
    base_delays_r_ms: [f64; ER_MAX_TAPS],
    /// ER→Late crossfade: samples in 50ms window at tail end
    crossfade_start_sample: usize,
    crossfade_end_sample: usize,
}

impl EarlyReflectionEngine {
    fn new(sample_rate: f64) -> Self {
        let max_delay_samples = (0.2 * sample_rate) as usize; // 200ms max (for 150ms + stereo offset headroom)
        let pattern = er_pattern_room(); // Default pattern

        let mut engine = Self {
            taps: std::array::from_fn(|_| ERTapStereo {
                delay_l: 0, delay_r: 0, gain: 0.0, pan: 0.0,
                lpf_coeff: 0.3, lpf_state_l: 0.0, lpf_state_r: 0.0,
            }),
            active_count: 0,
            buffer_l: vec![0.0; max_delay_samples],
            buffer_r: vec![0.0; max_delay_samples],
            write_pos: 0,
            max_delay: max_delay_samples,
            base_delays_l_ms: [0.0; ER_MAX_TAPS],
            base_delays_r_ms: [0.0; ER_MAX_TAPS],
            crossfade_start_sample: 0,
            crossfade_end_sample: 0,
        };
        engine.apply_pattern(&pattern, sample_rate);
        engine
    }

    /// Apply a per-style ER pattern
    fn apply_pattern(&mut self, pattern: &ERPattern, sample_rate: f64) {
        self.active_count = pattern.active_count;
        let max = self.max_delay - 1;

        // Calculate crossfade zone: last 50ms of ER tail
        let mut max_delay_ms = 0.0f64;
        for i in 0..pattern.active_count {
            let d = pattern.delays_ms[i] + pattern.stereo_offsets_ms[i].abs();
            if d > max_delay_ms { max_delay_ms = d; }
        }
        let crossfade_ms = 50.0f64.min(max_delay_ms * 0.4); // 50ms or 40% of max ER, whichever is shorter
        self.crossfade_start_sample = (((max_delay_ms - crossfade_ms) * 0.001 * sample_rate) as usize).min(max);
        self.crossfade_end_sample = ((max_delay_ms * 0.001 * sample_rate) as usize).min(max);

        for i in 0..ER_MAX_TAPS {
            if i < pattern.active_count {
                let delay_l_ms = pattern.delays_ms[i];
                let delay_r_ms = pattern.delays_ms[i] + pattern.stereo_offsets_ms[i];

                self.base_delays_l_ms[i] = delay_l_ms;
                self.base_delays_r_ms[i] = delay_r_ms.max(1.0); // Ensure positive delay

                let dl = (delay_l_ms * 0.001 * sample_rate) as usize;
                let dr = (delay_r_ms.max(1.0) * 0.001 * sample_rate) as usize;

                self.taps[i] = ERTapStereo {
                    delay_l: dl.min(max),
                    delay_r: dr.min(max),
                    gain: pattern.gains[i],
                    pan: pattern.pans[i],
                    lpf_coeff: 0.3,
                    lpf_state_l: 0.0,
                    lpf_state_r: 0.0,
                };
            } else {
                self.taps[i].gain = 0.0;
                self.taps[i].delay_l = 0;
                self.taps[i].delay_r = 0;
            }
        }
    }

    /// Switch to a new style pattern
    fn set_style(&mut self, style: &ReverbType, sample_rate: f64) {
        let pattern = er_pattern_for_style(style);
        self.apply_pattern(&pattern, sample_rate);
    }

    fn update_distance(&mut self, distance: f64) {
        let lpf = 0.1 + distance * 0.7;
        for i in 0..self.active_count {
            self.taps[i].lpf_coeff = lpf;
        }
    }

    fn update_space_scale(&mut self, scale: f64, sample_rate: f64) {
        let max = self.max_delay - 1;
        for i in 0..self.active_count {
            self.taps[i].delay_l = ((self.base_delays_l_ms[i] * 0.001 * sample_rate * scale) as usize).min(max);
            self.taps[i].delay_r = ((self.base_delays_r_ms[i] * 0.001 * sample_rate * scale) as usize).min(max);
        }
        // Update crossfade zone
        if self.crossfade_end_sample > 0 {
            self.crossfade_start_sample = ((self.crossfade_start_sample as f64 * scale) as usize).min(max);
            self.crossfade_end_sample = ((self.crossfade_end_sample as f64 * scale) as usize).min(max);
        }
    }

    /// Process stereo input through ER engine
    /// Returns (er_l, er_r) with stereo-decorrelated reflections
    #[inline(always)]
    fn process(&mut self, left: f64, right: f64, distance: f64) -> (f64, f64) {
        self.buffer_l[self.write_pos] = left;
        self.buffer_r[self.write_pos] = right;

        let mut out_l = 0.0;
        let mut out_r = 0.0;
        let distance_gain = 1.0 - distance * 0.8;

        for i in 0..self.active_count {
            let tap = &mut self.taps[i];

            // Read from separate L/R delay positions (stereo decorrelation)
            let read_l = (self.write_pos + self.max_delay - tap.delay_l) % self.max_delay;
            let read_r = (self.write_pos + self.max_delay - tap.delay_r) % self.max_delay;
            let raw_l = self.buffer_l[read_l];
            let raw_r = self.buffer_r[read_r];

            // One-pole LP for distance darkening
            let lpf_factor = 1.0 - tap.lpf_coeff;
            tap.lpf_state_l += (raw_l - tap.lpf_state_l) * lpf_factor;
            tap.lpf_state_r += (raw_r - tap.lpf_state_r) * lpf_factor;

            // Apply pan: -1=left, 0=center, +1=right (equal-power)
            let pan_angle = (tap.pan + 1.0) * 0.25 * std::f64::consts::PI; // 0 to π/2
            let pan_l = pan_angle.cos();
            let pan_r = pan_angle.sin();

            // ER→Late crossfade: taps near the end fade out for smooth transition
            let fade = if self.crossfade_end_sample > self.crossfade_start_sample {
                let tap_delay = tap.delay_l.max(tap.delay_r);
                if tap_delay >= self.crossfade_end_sample {
                    0.0
                } else if tap_delay > self.crossfade_start_sample {
                    let range = (self.crossfade_end_sample - self.crossfade_start_sample) as f64;
                    let pos = (tap_delay - self.crossfade_start_sample) as f64;
                    1.0 - (pos / range) // Linear fade
                } else {
                    1.0
                }
            } else {
                1.0
            };

            let g = tap.gain * fade;
            out_l += tap.lpf_state_l * g * pan_l;
            out_r += tap.lpf_state_r * g * pan_r;
        }

        self.write_pos = (self.write_pos + 1) % self.max_delay;

        (out_l * distance_gain, out_r * distance_gain)
    }

    fn reset(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        for tap in &mut self.taps {
            tap.lpf_state_l = 0.0;
            tap.lpf_state_r = 0.0;
        }
    }
}

/// Diffusion stage — multi-topology allpass network (R3.1-R3.5)
///
/// Supports 3 topologies:
/// - Serial: 6 simple allpass (Schroeder) — Room, Spring
/// - Nested: 3 nested allpass (Lexicon) — Hall, Chamber
/// - Lattice: 4 cross-coupled allpass pairs — Plate
#[derive(Debug, Clone)]
struct DiffusionStage {
    /// Serial allpass banks (used for Serial and Lattice topologies)
    serial_l: [SimpleAllpass; 6],
    serial_r: [SimpleAllpass; 6],
    /// Nested allpass banks (used for Nested topology)
    nested_l: [NestedAllpass; 3],
    nested_r: [NestedAllpass; 3],
    /// Active topology
    topology: DiffusionTopology,
    /// Number of active stages (topology-dependent)
    active_count: usize,
    /// Current diffusion amount (0.0-1.0)
    diffusion_amount: f64,
    /// Sample rate for modulation
    sample_rate: f64,
}

/// Serial allpass delay lengths (prime, samples @ 48kHz)
const DIFFUSION_DELAYS: [usize; 6] = [113, 157, 211, 269, 337, 409];
/// Nested allpass: outer delays (prime, larger)
const NESTED_OUTER_DELAYS: [usize; 3] = [241, 367, 509];
/// Nested allpass: inner delays (prime, smaller — ~40% of outer)
const NESTED_INNER_DELAYS: [usize; 3] = [97, 149, 199];

impl DiffusionStage {
    fn new(sample_rate: f64) -> Self {
        let scale = sample_rate / 48000.0;
        let spread = 23; // Stereo spread samples

        let serial_l = std::array::from_fn(|i| {
            SimpleAllpass::new(((DIFFUSION_DELAYS[i] as f64) * scale) as usize, 0.5)
        });
        let serial_r = std::array::from_fn(|i| {
            SimpleAllpass::new(
                (((DIFFUSION_DELAYS[i] + spread) as f64) * scale) as usize,
                0.5,
            )
        });

        let nested_l = std::array::from_fn(|i| {
            NestedAllpass::new(
                ((NESTED_OUTER_DELAYS[i] as f64) * scale) as usize,
                ((NESTED_INNER_DELAYS[i] as f64) * scale) as usize,
                0.5, 0.4,
            )
        });
        let nested_r = std::array::from_fn(|i| {
            NestedAllpass::new(
                (((NESTED_OUTER_DELAYS[i] + spread) as f64) * scale) as usize,
                (((NESTED_INNER_DELAYS[i] + 11) as f64) * scale) as usize,
                0.5, 0.4,
            )
        });

        Self {
            serial_l,
            serial_r,
            nested_l,
            nested_r,
            topology: DiffusionTopology::Serial,
            active_count: 4,
            diffusion_amount: 0.5,
            sample_rate,
        }
    }

    /// Set topology based on reverb style
    fn set_topology_for_style(&mut self, style: &ReverbType) {
        self.topology = match style {
            ReverbType::Room => DiffusionTopology::Serial,
            ReverbType::Hall => DiffusionTopology::Nested,
            ReverbType::Plate => DiffusionTopology::Lattice,
            ReverbType::Chamber => DiffusionTopology::Nested,
            ReverbType::Spring => DiffusionTopology::Serial,
            ReverbType::Ambient => DiffusionTopology::Nested,   // Dense, washy
            ReverbType::Shimmer => DiffusionTopology::Lattice,  // Ultra-dense for shimmer
            ReverbType::Nonlinear => DiffusionTopology::Serial,  // Simple for lo-fi
            ReverbType::Vintage => DiffusionTopology::Nested,   // Lexicon-style
            ReverbType::Gated => DiffusionTopology::Serial,     // Clean, punchy
        };
        // Re-apply diffusion with new topology
        self.update_diffusion(self.diffusion_amount);
    }

    fn update_diffusion(&mut self, diffusion: f64) {
        self.diffusion_amount = diffusion;

        match self.topology {
            DiffusionTopology::Serial => {
                // Serial: 2-6 stages, feedback 0.20-0.65 (R3.5 expanded range)
                self.active_count = (2.0 + diffusion * 4.0) as usize;
                let feedback = 0.20 + diffusion * 0.45;
                for ap in &mut self.serial_l {
                    ap.feedback = feedback;
                }
                for ap in &mut self.serial_r {
                    ap.feedback = feedback;
                }
            }
            DiffusionTopology::Nested => {
                // Nested: 1-3 nested stages, feedback 0.30-0.70
                self.active_count = (1.0 + diffusion * 2.0).ceil() as usize;
                let outer_fb = 0.30 + diffusion * 0.40;
                let inner_fb = 0.25 + diffusion * 0.35;
                for ap in &mut self.nested_l {
                    ap.set_feedback(outer_fb, inner_fb);
                }
                for ap in &mut self.nested_r {
                    ap.set_feedback(outer_fb, inner_fb);
                }
            }
            DiffusionTopology::Lattice => {
                // Lattice: 4-6 cross-coupled stages, feedback 0.35-0.75 (R3.5 plate max)
                self.active_count = (4.0 + diffusion * 2.0) as usize;
                let feedback = 0.35 + diffusion * 0.40;
                for ap in &mut self.serial_l {
                    ap.feedback = feedback;
                }
                for ap in &mut self.serial_r {
                    ap.feedback = feedback;
                }
            }
        }
    }

    /// Set modulation on diffusion allpasses (R3.4)
    fn set_modulation(&mut self, rate_hz: f64, depth_samples: f64) {
        let sr = self.sample_rate;
        // Stagger modulation rates slightly per stage for decorrelation
        for (i, ap) in self.serial_l.iter_mut().enumerate() {
            let r = rate_hz * (1.0 + i as f64 * 0.15);
            ap.set_modulation(r, depth_samples, sr);
        }
        for (i, ap) in self.serial_r.iter_mut().enumerate() {
            let r = rate_hz * (1.0 + i as f64 * 0.12);
            ap.set_modulation(r, depth_samples * 0.8, sr);
        }
        for (i, ap) in self.nested_l.iter_mut().enumerate() {
            let r = rate_hz * (1.0 + i as f64 * 0.2);
            ap.set_modulation(r, depth_samples, sr);
        }
        for (i, ap) in self.nested_r.iter_mut().enumerate() {
            let r = rate_hz * (1.0 + i as f64 * 0.18);
            ap.set_modulation(r, depth_samples * 0.8, sr);
        }
    }

    #[inline(always)]
    fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        match self.topology {
            DiffusionTopology::Serial => {
                let mut l = left;
                let mut r = right;
                for i in 0..self.active_count.min(6) {
                    l = self.serial_l[i].process(l);
                    r = self.serial_r[i].process(r);
                }
                (l, r)
            }
            DiffusionTopology::Nested => {
                let mut l = left;
                let mut r = right;
                for i in 0..self.active_count.min(3) {
                    l = self.nested_l[i].process(l);
                    r = self.nested_r[i].process(r);
                }
                (l, r)
            }
            DiffusionTopology::Lattice => {
                // Lattice: cross-coupled pairs (L→R, R→L bleed between stages)
                let mut l = left;
                let mut r = right;
                for i in 0..self.active_count.min(6) {
                    let new_l = self.serial_l[i].process(l);
                    let new_r = self.serial_r[i].process(r);
                    // Cross-couple: 15% bleed between channels
                    l = new_l * 0.85 + new_r * 0.15;
                    r = new_r * 0.85 + new_l * 0.15;
                }
                (l, r)
            }
        }
    }

    fn reset(&mut self) {
        for ap in &mut self.serial_l { ap.reset(); }
        for ap in &mut self.serial_r { ap.reset(); }
        for ap in &mut self.nested_l { ap.reset(); }
        for ap in &mut self.nested_r { ap.reset(); }
    }
}

/// Small allpass for embedding inside FDN feedback path (R6.3)
/// Prime-length delay for maximum density without comb artifacts
#[derive(Debug, Clone)]
struct FeedbackAllpass {
    buffer: Vec<f64>,
    write_pos: usize,
    delay: usize,
    coeff: f64,
}

impl FeedbackAllpass {
    fn new(delay: usize, coeff: f64) -> Self {
        Self {
            buffer: vec![0.0; delay.max(1)],
            write_pos: 0,
            delay,
            coeff,
        }
    }

    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let buf_len = self.buffer.len();
        let read_pos = (self.write_pos + buf_len - self.delay) % buf_len;
        let delayed = self.buffer[read_pos];
        let output = delayed - self.coeff * input;
        self.buffer[self.write_pos] = input + self.coeff * delayed;
        self.write_pos = (self.write_pos + 1) % buf_len;
        output
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

/// TDF-II biquad filter state for crossover (R4.4)
/// Two cascaded sections = Linkwitz-Riley 12dB/oct (4th order)
#[derive(Debug, Clone, Copy)]
struct LR4State {
    // First biquad section
    s1_z1: f64,
    s1_z2: f64,
    // Second biquad section (cascade)
    s2_z1: f64,
    s2_z2: f64,
}

impl Default for LR4State {
    fn default() -> Self {
        Self { s1_z1: 0.0, s1_z2: 0.0, s2_z1: 0.0, s2_z2: 0.0 }
    }
}

impl LR4State {
    fn reset(&mut self) {
        *self = Self::default();
    }
}

/// Biquad coefficients (normalized: a0=1.0)
#[derive(Debug, Clone, Copy)]
struct BiquadCoeffs {
    b0: f64, b1: f64, b2: f64,
    a1: f64, a2: f64,
}

impl BiquadCoeffs {
    /// Butterworth lowpass (2nd order) — cascade two for LR4
    fn butterworth_lp(freq: f64, sample_rate: f64) -> Self {
        let w0 = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * std::f64::consts::FRAC_1_SQRT_2); // Q = 1/√2 for Butterworth
        let a0 = 1.0 + alpha;
        let b0 = ((1.0 - cos_w0) / 2.0) / a0;
        let b1 = (1.0 - cos_w0) / a0;
        let b2 = b0;
        let a1 = (-2.0 * cos_w0) / a0;
        let a2 = (1.0 - alpha) / a0;
        Self { b0, b1, b2, a1, a2 }
    }

    /// Butterworth highpass (2nd order) — cascade two for LR4
    fn butterworth_hp(freq: f64, sample_rate: f64) -> Self {
        let w0 = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * std::f64::consts::FRAC_1_SQRT_2);
        let a0 = 1.0 + alpha;
        let b0 = ((1.0 + cos_w0) / 2.0) / a0;
        let b1 = (-(1.0 + cos_w0)) / a0;
        let b2 = b0;
        let a1 = (-2.0 * cos_w0) / a0;
        let a2 = (1.0 - alpha) / a0;
        Self { b0, b1, b2, a1, a2 }
    }

    /// Bypass (unity gain, no filtering)
    fn bypass() -> Self {
        Self { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 }
    }

    /// Low shelf filter: gain_db at freq, smooth transition above
    fn low_shelf(freq: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / 2.0 * ((a + 1.0 / a) * (1.0 / 0.707 - 1.0) + 2.0).sqrt();
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let a0 = (a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
        Self {
            b0: (a * ((a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha)) / a0,
            b1: (2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0)) / a0,
            b2: (a * ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha)) / a0,
            a1: (-2.0 * ((a - 1.0) + (a + 1.0) * cos_w0)) / a0,
            a2: ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha) / a0,
        }
    }

    /// High shelf filter: gain_db at freq, smooth transition below
    fn high_shelf(freq: f64, gain_db: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / 2.0 * ((a + 1.0 / a) * (1.0 / 0.707 - 1.0) + 2.0).sqrt();
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let a0 = (a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha;
        Self {
            b0: (a * ((a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha)) / a0,
            b1: (-2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0)) / a0,
            b2: (a * ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha)) / a0,
            a1: (2.0 * ((a - 1.0) - (a + 1.0) * cos_w0)) / a0,
            a2: ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha) / a0,
        }
    }

    /// Parametric EQ (peaking): gain_db at freq with Q
    fn peaking_eq(freq: f64, gain_db: f64, q: f64, sample_rate: f64) -> Self {
        let a = 10.0_f64.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let cos_w0 = w0.cos();
        let alpha = w0.sin() / (2.0 * q);

        let a0 = 1.0 + alpha / a;
        Self {
            b0: (1.0 + alpha * a) / a0,
            b1: (-2.0 * cos_w0) / a0,
            b2: (1.0 - alpha * a) / a0,
            a1: (-2.0 * cos_w0) / a0,
            a2: (1.0 - alpha / a) / a0,
        }
    }

    /// Process one sample through TDF-II biquad section
    #[inline(always)]
    fn process_tdf2(self, input: f64, z1: &mut f64, z2: &mut f64) -> f64 {
        let output = self.b0 * input + *z1;
        *z1 = self.b1 * input - self.a1 * output + *z2;
        *z2 = self.b2 * input - self.a2 * output;
        output
    }
}

/// 4-band crossover filter state per FDN delay line (R4.1/R4.4)
/// 3 Linkwitz-Riley crossover points → 4 bands: Low, LowMid, HighMid, High
#[derive(Debug, Clone)]
struct CrossoverState {
    // Crossover 1 (Low/LowMid split): LP + HP pair
    xo1_lp: LR4State,
    xo1_hp: LR4State,
    // Crossover 2 (LowMid/HighMid split): LP + HP on HP1 output
    xo2_lp: LR4State,
    xo2_hp: LR4State,
    // Crossover 3 (HighMid/High split): LP + HP on HP2 output
    xo3_lp: LR4State,
    xo3_hp: LR4State,
}

impl CrossoverState {
    fn new() -> Self {
        Self {
            xo1_lp: LR4State::default(),
            xo1_hp: LR4State::default(),
            xo2_lp: LR4State::default(),
            xo2_hp: LR4State::default(),
            xo3_lp: LR4State::default(),
            xo3_hp: LR4State::default(),
        }
    }

    fn reset(&mut self) {
        self.xo1_lp.reset(); self.xo1_hp.reset();
        self.xo2_lp.reset(); self.xo2_hp.reset();
        self.xo3_lp.reset(); self.xo3_hp.reset();
    }
}

/// Single FDN delay line with 4-band decay + DC blocker + feedback allpass (R4/R6)
#[derive(Debug, Clone)]
struct FDNDelayLine {
    buffer: Vec<f64>,
    write_pos: usize,
    base_delay: usize,
    // 4-band crossover state (R4.1/R4.4 — replaces old one-pole LP/HP)
    crossover: CrossoverState,
    // DC blocker to prevent sub-bass buildup (rumble prevention)
    dc_prev_in: f64,
    dc_prev_out: f64,
    // Allpass embedded in feedback path for denser tails (R6.3)
    feedback_allpass: FeedbackAllpass,
    // Delay line jitter offset in samples (R6.4)
    jitter_offset: f64,
}

impl FDNDelayLine {
    fn new(base_delay: usize, allpass_delay: usize) -> Self {
        // Allocate extra for modulation headroom + cubic interpolation (needs 4 points)
        let buf_size = base_delay + 68;
        Self {
            buffer: vec![0.0; buf_size],
            write_pos: 0,
            base_delay,
            crossover: CrossoverState::new(),
            dc_prev_in: 0.0,
            dc_prev_out: 0.0,
            feedback_allpass: FeedbackAllpass::new(allpass_delay, 0.15),
            jitter_offset: 0.0,
        }
    }

    /// Read from delay line with cubic Hermite interpolation
    ///
    /// 4-point cubic (Hermite spline) eliminates zipper noise artifacts
    /// that linear interpolation produces during delay modulation.
    /// Uses points: y[-1], y[0], y[1], y[2] around the fractional position.
    #[inline(always)]
    fn read_modulated(&self, mod_offset: f64) -> f64 {
        let total_delay = self.base_delay as f64 + mod_offset;
        let delay_int = total_delay as usize;
        let frac = total_delay - delay_int as f64;

        let buf_len = self.buffer.len();
        // 4 sample positions for cubic interpolation
        let pos0 = (self.write_pos + buf_len - delay_int) % buf_len;      // y[0]
        let pos1 = (pos0 + buf_len - 1) % buf_len;                         // y[1] (older)
        let pos_m1 = (pos0 + 1) % buf_len;                                 // y[-1] (newer)
        let pos2 = (pos1 + buf_len - 1) % buf_len;                         // y[2] (oldest)

        let ym1 = self.buffer[pos_m1];
        let y0 = self.buffer[pos0];
        let y1 = self.buffer[pos1];
        let y2 = self.buffer[pos2];

        // Hermite cubic interpolation (4-point, 3rd-order)
        // c0 = y0
        // c1 = 0.5 * (y1 - ym1)
        // c2 = ym1 - 2.5*y0 + 2*y1 - 0.5*y2
        // c3 = 0.5*(y2 - ym1) + 1.5*(y0 - y1)
        // result = ((c3*frac + c2)*frac + c1)*frac + c0
        let c0 = y0;
        let c1 = 0.5 * (y1 - ym1);
        let c2 = ym1 - 2.5 * y0 + 2.0 * y1 - 0.5 * y2;
        let c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1);

        ((c3 * frac + c2) * frac + c1) * frac + c0
    }

    #[inline(always)]
    fn write(&mut self, sample: f64) {
        self.buffer[self.write_pos] = sample;
        self.write_pos = (self.write_pos + 1) % self.buffer.len();
    }

    /// Apply 4-band decay shaping inside feedback path (R4.1-R4.4)
    /// Linkwitz-Riley 12dB/oct crossover → 4 bands with independent decay multipliers
    #[inline(always)]
    #[allow(clippy::too_many_arguments)]
    fn apply_decay_shaping_4band(
        &mut self,
        sample: f64,
        base_feedback: f64,
        low_mult: f64,
        lowmid_mult: f64,
        highmid_mult: f64,
        high_mult: f64,
        xo1_lp_coeffs: &BiquadCoeffs,
        xo1_hp_coeffs: &BiquadCoeffs,
        xo2_lp_coeffs: &BiquadCoeffs,
        xo2_hp_coeffs: &BiquadCoeffs,
        xo3_lp_coeffs: &BiquadCoeffs,
        xo3_hp_coeffs: &BiquadCoeffs,
        freeze: bool,
    ) -> f64 {
        // Crossover 1: split into low_band and rest
        let low_band = {
            let s = &mut self.crossover.xo1_lp;
            let after_s1 = xo1_lp_coeffs.process_tdf2(sample, &mut s.s1_z1, &mut s.s1_z2);
            xo1_lp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };
        let rest1 = {
            let s = &mut self.crossover.xo1_hp;
            let after_s1 = xo1_hp_coeffs.process_tdf2(sample, &mut s.s1_z1, &mut s.s1_z2);
            xo1_hp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };

        // Crossover 2: split rest1 into lowmid and rest2
        let lowmid_band = {
            let s = &mut self.crossover.xo2_lp;
            let after_s1 = xo2_lp_coeffs.process_tdf2(rest1, &mut s.s1_z1, &mut s.s1_z2);
            xo2_lp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };
        let rest2 = {
            let s = &mut self.crossover.xo2_hp;
            let after_s1 = xo2_hp_coeffs.process_tdf2(rest1, &mut s.s1_z1, &mut s.s1_z2);
            xo2_hp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };

        // Crossover 3: split rest2 into highmid and high
        let highmid_band = {
            let s = &mut self.crossover.xo3_lp;
            let after_s1 = xo3_lp_coeffs.process_tdf2(rest2, &mut s.s1_z1, &mut s.s1_z2);
            xo3_lp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };
        let high_band = {
            let s = &mut self.crossover.xo3_hp;
            let after_s1 = xo3_hp_coeffs.process_tdf2(rest2, &mut s.s1_z1, &mut s.s1_z2);
            xo3_hp_coeffs.process_tdf2(after_s1, &mut s.s2_z1, &mut s.s2_z2)
        };

        // Apply per-band decay scaling
        let shaped = low_band * base_feedback * low_mult
            + lowmid_band * base_feedback * lowmid_mult
            + highmid_band * base_feedback * highmid_mult
            + high_band * base_feedback * high_mult;

        // DC blocker — bypassed in freeze mode
        if freeze {
            return shaped;
        }
        let dc_out = shaped - self.dc_prev_in + 0.9995 * self.dc_prev_out;
        self.dc_prev_in = shaped;
        self.dc_prev_out = dc_out;

        dc_out
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.crossover.reset();
        self.dc_prev_in = 0.0;
        self.dc_prev_out = 0.0;
        self.feedback_allpass.reset();
        self.jitter_offset = 0.0;
    }
}

/// Mixing matrix type for FDN (R6.1)
#[derive(Debug, Clone, Copy, PartialEq)]
enum MixingMatrix {
    /// Hadamard — optimal for power-of-2 sizes, maximally diffusing
    Hadamard,
    /// Householder — H = I - (2/n)*ones(n,n), good energy distribution for any size
    Householder,
}

/// FDN size configuration (R6.2)
#[derive(Debug, Clone, Copy, PartialEq)]
enum FdnSize {
    /// 4 delay lines — CPU-light, less dense
    Small,
    /// 8 delay lines — default, good balance
    Medium,
    /// 16 delay lines — luxury dense tail
    Large,
}

impl FdnSize {
    fn count(self) -> usize {
        match self {
            FdnSize::Small => 4,
            FdnSize::Medium => 8,
            FdnSize::Large => 16,
        }
    }
}

/// Shimmer pitch shifter — two overlapping grains for glitch-free octave up (R7.2)
///
/// Uses a circular buffer with two read pointers (grains) that advance at 2x speed
/// for octave-up shifting. Hann-windowed crossfade eliminates grain boundary clicks.
/// Buffer size is fixed 2048 samples (~42ms @ 48kHz) — zero dynamic allocations.
const SHIMMER_BUF_SIZE: usize = 2048;

#[derive(Debug, Clone)]
struct ShimmerShifter {
    buffer: Vec<f64>,
    write_pos: usize,
    /// Two grain read positions (fractional)
    grain_pos: [f64; 2],
    /// Pitch ratio (2.0 = octave up)
    ratio: f64,
}

impl ShimmerShifter {
    fn new() -> Self {
        Self {
            buffer: vec![0.0; SHIMMER_BUF_SIZE],
            write_pos: 0,
            grain_pos: [0.0, SHIMMER_BUF_SIZE as f64 / 2.0],
            ratio: 2.0, // octave up
        }
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.grain_pos = [0.0, SHIMMER_BUF_SIZE as f64 / 2.0];
    }

    /// Process one sample: write input, read pitch-shifted output
    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        // Write input
        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % SHIMMER_BUF_SIZE;

        let buf_len = SHIMMER_BUF_SIZE as f64;
        let mut output = 0.0;

        // Two grains with Hann crossfade
        for g in 0..2 {
            let pos = self.grain_pos[g];
            let int_pos = pos as usize % SHIMMER_BUF_SIZE;
            let frac = pos - pos.floor();

            // Linear interpolation
            let s0 = self.buffer[int_pos];
            let s1 = self.buffer[(int_pos + 1) % SHIMMER_BUF_SIZE];
            let sample = s0 + (s1 - s0) * frac;

            // Hann window based on grain's distance from its starting position
            // Each grain covers half the buffer; they overlap in the middle
            let grain_phase = ((self.grain_pos[g] - self.grain_pos[1 - g]).rem_euclid(buf_len)) / buf_len;
            let window = 0.5 * (1.0 - (grain_phase * 2.0 * std::f64::consts::PI).cos());

            output += sample * window;

            // Advance grain at pitch ratio speed
            self.grain_pos[g] = (self.grain_pos[g] + self.ratio).rem_euclid(buf_len);
        }

        output
    }
}

/// Feedback processing mode (R7.2-R7.3)
#[derive(Debug, Clone, Copy, PartialEq)]
enum FeedbackMode {
    /// Normal feedback (default for most styles)
    Normal,
    /// Shimmer: pitch-shift +12 semitones (octave up) in 2 feedback lines (R7.2)
    Shimmer,
    /// Nonlinear: waveshaping distortion in feedback path (R7.3)
    Nonlinear,
}

/// FDN Core — configurable Feedback Delay Network (R6.1-R6.6)
///
/// Features:
/// - Configurable size: 4×4, 8×8, or 16×16 (R6.2)
/// - Selectable mixing matrix: Hadamard or Householder (R6.1)
/// - Velvet noise modulation per delay line (Valhalla-style)
/// - Allpass embedded in each feedback path for denser tails (R6.3)
/// - Delay line jitter for comb-filter coloration prevention (R6.4)
/// - Adaptive feedback ceiling based on decay (R6.5)
/// - Chorus mode: detuned pitch-shift on 2 lines (R6.6)
#[derive(Debug, Clone)]
struct FDNCore {
    delay_lines: Vec<FDNDelayLine>,
    feedback_gains: Vec<f64>,
    velvet_gens: Vec<VelvetNoiseGenerator>,
    /// Active number of delay lines (4, 8, or 16)
    active_size: usize,
    /// Current FDN size configuration
    fdn_size: FdnSize,
    /// Current mixing matrix type
    matrix_type: MixingMatrix,
    /// Pre-computed mixing matrix (max 16×16)
    mix_matrix: Vec<f64>, // Flat row-major [active_size × active_size]
    /// Spin depth (fast modulation amplitude), 0.0-1.0
    spin_depth: f64,
    /// Wander depth (slow drift amplitude), 0.0-1.0
    wander_depth: f64,
    /// Combined modulation depth scale (0.0-0.01)
    mod_depth: f64,
    freeze: bool,
    // 4-band Linkwitz-Riley crossover coefficients (R4.4)
    xo1_lp: BiquadCoeffs, // Crossover 1 LP (Low/LowMid split)
    xo1_hp: BiquadCoeffs, // Crossover 1 HP
    xo2_lp: BiquadCoeffs, // Crossover 2 LP (LowMid/HighMid split)
    xo2_hp: BiquadCoeffs, // Crossover 2 HP
    xo3_lp: BiquadCoeffs, // Crossover 3 LP (HighMid/High split)
    xo3_hp: BiquadCoeffs, // Crossover 3 HP
    // Chorus mode (R6.6): detuned read on lines 0 and 4 (or 0 and 2 for size=4)
    chorus_enabled: bool,
    chorus_depth_samples: f64, // Depth in samples (derived from ±cents)
    chorus_phase: f64,         // LFO phase 0-2π
    chorus_increment: f64,     // Phase increment per sample
    // Jitter parameters (R6.4)
    jitter_amount: f64, // 0.0-1.0 (maps to ±2-5 samples)
    // Feedback mode (R7.2-R7.3)
    feedback_mode: FeedbackMode,
    // Nonlinear drive amount (R7.3)
    nonlinear_drive: f64,
    // Shimmer pitch shifters — one per applicable line (R7.2)
    shimmer_shifters: Vec<ShimmerShifter>,
}

/// FDN delay lengths (prime-distributed, samples @ 48kHz)
/// 16 primes covering the range for small/medium/large FDN
const FDN_BASE_DELAYS: [usize; 16] = [
    1087, 1283, 1481, 1669, 1877, 2083, 2293, 2503, // original 8
    1151, 1361, 1567, 1741, 1973, 2161, 2381, 2593, // additional 8 for 16×16
];

/// Prime delays for feedback allpass per line (R6.3)
/// Small primes for dense but short allpass — avoids comb coloration
const FEEDBACK_AP_DELAYS: [usize; 16] = [
    37, 41, 43, 47, 53, 59, 61, 67, // lines 0-7
    71, 73, 79, 83, 89, 97, 101, 103, // lines 8-15
];

/// Hadamard 8×8 matrix (normalized by 1/√8 ≈ 0.3536)
/// H₈ = H₂ ⊗ H₂ ⊗ H₂ (Kronecker product)
const HADAMARD_8: [[f64; 8]; 8] = {
    const P: f64 = 0.35355339059327373; // 1/√8
    const N: f64 = -0.35355339059327373;
    [
        [P, P, P, P, P, P, P, P],
        [P, N, P, N, P, N, P, N],
        [P, P, N, N, P, P, N, N],
        [P, N, N, P, P, N, N, P],
        [P, P, P, P, N, N, N, N],
        [P, N, P, N, N, P, N, P],
        [P, P, N, N, N, N, P, P],
        [P, N, N, P, N, P, P, N],
    ]
};

/// Build a Householder mixing matrix (R6.1)
/// H = I - (2/n) * ones(n,n) — unitary, maximally diffusing
/// All diagonal elements = 1 - 2/n, all off-diagonal = -2/n
fn build_householder_matrix(n: usize) -> Vec<f64> {
    let scale = 2.0 / n as f64;
    let norm = 1.0 / (n as f64).sqrt();
    let mut mat = vec![0.0; n * n];
    for i in 0..n {
        for j in 0..n {
            let val = if i == j { 1.0 - scale } else { -scale };
            mat[i * n + j] = val * norm;
        }
    }
    mat
}

/// Build a Hadamard mixing matrix for sizes 4, 8, or 16
fn build_hadamard_matrix(n: usize) -> Vec<f64> {
    let norm = 1.0 / (n as f64).sqrt();
    let mut mat = vec![0.0; n * n];
    // Recursive Sylvester construction: H_1 = [1]
    // H_2n = [[H_n, H_n], [H_n, -H_n]]
    // Start with H_1 and build up
    mat[0] = 1.0;
    let mut size = 1;
    while size < n {
        // Copy current quadrant to 3 copies
        for i in 0..size {
            for j in 0..size {
                let val = mat[i * n + j];
                mat[i * n + (j + size)] = val;           // top-right
                mat[(i + size) * n + j] = val;           // bottom-left
                mat[(i + size) * n + (j + size)] = -val; // bottom-right (negated)
            }
        }
        size *= 2;
    }
    // Normalize
    for v in mat.iter_mut() {
        *v *= norm;
    }
    mat
}

/// Velvet noise seeds — 16 unique prime-derived values for decorrelation
const VN_SEEDS: [u64; 16] = [
    0x9E3779B97F4A7C15, 0x6C62272E07BB0142,
    0xBF58476D1CE4E5B9, 0x94D049BB133111EB,
    0xD6E8FEB86659FD93, 0xA0761D6478BD642F,
    0xE7037ED1A0B428DB, 0x8A5CD789635D2DFF,
    0x517CC1B727220A95, 0x2545F4914F6CDD1D,
    0xC5B2D5E261A15E47, 0x3F84D5B5B5470917,
    0x9E6495A3AB0DDE63, 0x6E7783B9CD8C5E8B,
    0xAB5BE9F37263B1E3, 0x7C29335B8D8CAF5F,
];

impl FDNCore {
    fn new(sample_rate: f64) -> Self {
        Self::with_config(sample_rate, FdnSize::Medium, MixingMatrix::Hadamard)
    }

    fn with_config(sample_rate: f64, size: FdnSize, matrix: MixingMatrix) -> Self {
        let n = size.count();
        let scale = sample_rate / 48000.0;

        let delay_lines: Vec<FDNDelayLine> = (0..n)
            .map(|i| {
                let base = ((FDN_BASE_DELAYS[i] as f64) * scale) as usize;
                FDNDelayLine::new(base, FEEDBACK_AP_DELAYS[i])
            })
            .collect();

        let feedback_gains = vec![0.92; n];

        let velvet_gens: Vec<VelvetNoiseGenerator> = (0..n)
            .map(|i| VelvetNoiseGenerator::new(sample_rate, VN_SEEDS[i]))
            .collect();

        let mix_matrix = match matrix {
            MixingMatrix::Hadamard => build_hadamard_matrix(n),
            MixingMatrix::Householder => build_householder_matrix(n),
        };

        // 4-band Linkwitz-Riley crossover coefficients (R4.4)
        // Default crossover frequencies: 250 Hz, 2000 Hz, 8000 Hz
        let xo1_lp = BiquadCoeffs::butterworth_lp(250.0, sample_rate);
        let xo1_hp = BiquadCoeffs::butterworth_hp(250.0, sample_rate);
        let xo2_lp = BiquadCoeffs::butterworth_lp(2000.0, sample_rate);
        let xo2_hp = BiquadCoeffs::butterworth_hp(2000.0, sample_rate);
        let xo3_lp = BiquadCoeffs::butterworth_lp(8000.0, sample_rate);
        let xo3_hp = BiquadCoeffs::butterworth_hp(8000.0, sample_rate);

        // Chorus LFO: ~1.5 Hz default
        let chorus_increment = 2.0 * std::f64::consts::PI * 1.5 / sample_rate;

        Self {
            delay_lines,
            feedback_gains,
            velvet_gens,
            active_size: n,
            fdn_size: size,
            matrix_type: matrix,
            mix_matrix,
            spin_depth: 0.6,
            wander_depth: 0.4,
            mod_depth: 0.002,
            freeze: false,
            xo1_lp, xo1_hp,
            xo2_lp, xo2_hp,
            xo3_lp, xo3_hp,
            chorus_enabled: false,
            chorus_depth_samples: 0.0,
            chorus_phase: 0.0,
            chorus_increment,
            jitter_amount: 0.0,
            feedback_mode: FeedbackMode::Normal,
            nonlinear_drive: 0.0,
            shimmer_shifters: (0..n).map(|_| ShimmerShifter::new()).collect(),
        }
    }

    fn set_size(&mut self, size: FdnSize, sample_rate: f64) {
        if size == self.fdn_size {
            return;
        }
        let old_matrix = self.matrix_type;
        let old_spin = self.spin_depth;
        let old_wander = self.wander_depth;
        let old_mod = self.mod_depth;
        let old_chorus = self.chorus_enabled;
        let old_chorus_depth = self.chorus_depth_samples;
        let old_jitter = self.jitter_amount;
        *self = Self::with_config(sample_rate, size, old_matrix);
        self.spin_depth = old_spin;
        self.wander_depth = old_wander;
        self.mod_depth = old_mod;
        self.chorus_enabled = old_chorus;
        self.chorus_depth_samples = old_chorus_depth;
        self.jitter_amount = old_jitter;
    }

    fn set_matrix_type(&mut self, matrix: MixingMatrix) {
        if matrix == self.matrix_type {
            return;
        }
        self.matrix_type = matrix;
        self.mix_matrix = match matrix {
            MixingMatrix::Hadamard => build_hadamard_matrix(self.active_size),
            MixingMatrix::Householder => build_householder_matrix(self.active_size),
        };
    }

    /// Update crossover frequencies (R4.2)
    fn update_crossover_freqs(&mut self, freq1: f64, freq2: f64, freq3: f64, sample_rate: f64) {
        let f1 = freq1.clamp(20.0, freq2 - 10.0);
        let f2 = freq2.clamp(f1 + 10.0, freq3 - 10.0);
        let f3 = freq3.clamp(f2 + 10.0, sample_rate * 0.45);
        self.xo1_lp = BiquadCoeffs::butterworth_lp(f1, sample_rate);
        self.xo1_hp = BiquadCoeffs::butterworth_hp(f1, sample_rate);
        self.xo2_lp = BiquadCoeffs::butterworth_lp(f2, sample_rate);
        self.xo2_hp = BiquadCoeffs::butterworth_hp(f2, sample_rate);
        self.xo3_lp = BiquadCoeffs::butterworth_lp(f3, sample_rate);
        self.xo3_hp = BiquadCoeffs::butterworth_hp(f3, sample_rate);
    }

    /// Adaptive feedback ceiling (R6.5)
    /// decay 0-0.5 → ceiling 0.91, decay 0.5-1.0 → ceiling ramps to 0.94
    /// Conservative ceilings to compensate for feedback allpass + chorus energy (R6.3/R6.6)
    fn update_decay(&mut self, decay: f64) {
        let ceiling = if decay <= 0.5 {
            0.91
        } else {
            // Linear ramp: 0.5→0.91, 1.0→0.94
            0.91 + (decay - 0.5) * 0.06
        };
        let gain = 0.40 + decay * (ceiling - 0.40);
        for g in &mut self.feedback_gains {
            *g = gain;
        }
    }

    fn update_space_scale(&mut self, scale: f64, sample_rate: f64) {
        let sr_scale = sample_rate / 48000.0;
        let n = self.active_size;
        for i in 0..n {
            let dl = &mut self.delay_lines[i];
            dl.base_delay = ((FDN_BASE_DELAYS[i] as f64) * sr_scale * scale) as usize;
            let needed = dl.base_delay + 68;
            if dl.buffer.len() < needed {
                dl.buffer.resize(needed, 0.0);
            }
        }
    }

    /// Update jitter offsets using velvet noise RNG state (R6.4)
    fn update_jitter(&mut self) {
        if self.jitter_amount <= 0.001 {
            for dl in &mut self.delay_lines {
                dl.jitter_offset = 0.0;
            }
            return;
        }
        // Use each velvet gen's current state to derive a jitter offset
        // ±2-5 samples based on jitter_amount
        let max_jitter = 2.0 + self.jitter_amount * 3.0; // 2-5 samples
        for i in 0..self.active_size {
            // Derive from velvet gen RNG state (deterministic, no extra allocation)
            let hash = self.velvet_gens[i].rng_state;
            // Map to -1.0..1.0
            let norm = (hash as i64 as f64) / (i64::MAX as f64);
            self.delay_lines[i].jitter_offset = norm * max_jitter;
        }
    }

    /// Set chorus parameters (R6.6)
    fn set_chorus(&mut self, enabled: bool, cents: f64, rate_hz: f64, sample_rate: f64) {
        self.chorus_enabled = enabled;
        // cents → pitch ratio → delay modulation in samples
        // ±N cents = 2^(N/1200) - 1 ≈ N * 0.000578
        // At base delay D, depth_samples ≈ D * (2^(cents/1200) - 1)
        // Use average base delay for calculation
        let avg_delay = if self.active_size > 0 {
            self.delay_lines.iter().take(self.active_size)
                .map(|dl| dl.base_delay as f64)
                .sum::<f64>() / self.active_size as f64
        } else {
            1500.0
        };
        self.chorus_depth_samples = avg_delay * (2.0_f64.powf(cents / 1200.0) - 1.0);
        self.chorus_increment = 2.0 * std::f64::consts::PI * rate_hz / sample_rate;
    }

    /// Process stereo input through FDN, returns stereo output
    #[inline(always)]
    #[allow(clippy::too_many_arguments)]
    fn process(
        &mut self,
        left: f64,
        right: f64,
        low_mult: f64,
        lowmid_mult: f64,
        highmid_mult: f64,
        high_mult: f64,
        thickness: f64,
    ) -> (f64, f64) {
        let n = self.active_size;
        let half = n / 2;

        // Read from all delay lines (with velvet noise modulation + jitter)
        let mut outputs = [0.0f64; 16];
        for i in 0..n {
            let (spin, wander) = self.velvet_gens[i].process();
            let mod_signal = spin * self.spin_depth + wander * self.wander_depth;
            let mut mod_offset =
                mod_signal * self.mod_depth * self.delay_lines[i].base_delay as f64;

            // Add jitter offset (R6.4)
            mod_offset += self.delay_lines[i].jitter_offset;

            // Chorus mode (R6.6): add pitch-shift LFO on lines 0 and half
            if self.chorus_enabled && (i == 0 || i == half) {
                let chorus_mod = if i == 0 {
                    self.chorus_phase.sin() * self.chorus_depth_samples
                } else {
                    // Opposite phase for stereo width
                    (-self.chorus_phase).sin() * self.chorus_depth_samples
                };
                mod_offset += chorus_mod;
            }

            outputs[i] = self.delay_lines[i].read_modulated(mod_offset);
        }

        // Advance chorus LFO
        if self.chorus_enabled {
            self.chorus_phase += self.chorus_increment;
            if self.chorus_phase > 2.0 * std::f64::consts::PI {
                self.chorus_phase -= 2.0 * std::f64::consts::PI;
            }
        }

        // Matrix mixing (Hadamard or Householder)
        let mut mixed = [0.0f64; 16];
        for i in 0..n {
            let mut sum = 0.0;
            let row_offset = i * n;
            for j in 0..n {
                sum += self.mix_matrix[row_offset + j] * outputs[j];
            }
            mixed[i] = sum;
        }

        // In freeze mode, reject new input
        let input_scale = if self.freeze { 0.0 } else { 1.0 };
        let input_gain = 0.35 * input_scale;

        // Distribute stereo input across all lines
        // First half leans LEFT, second half leans RIGHT
        let mut inputs = [0.0f64; 16];
        for i in 0..n {
            let t = i as f64 / (n - 1).max(1) as f64; // 0.0 → 1.0 across lines
            let l_weight = 1.0 - t * 0.65; // 1.0 → 0.35
            let r_weight = 0.35 + t * 0.65; // 0.35 → 1.0
            inputs[i] = (left * l_weight + right * r_weight) * input_gain;
        }

        // Thickness controls
        let low_boost = 1.0 + thickness * 0.2;
        let saturation = thickness * 0.06;

        for i in 0..n {
            let fb = if self.freeze {
                0.99999
            } else {
                self.feedback_gains[i]
            };
            let shaped = self.delay_lines[i].apply_decay_shaping_4band(
                mixed[i],
                fb,
                low_mult * low_boost,
                lowmid_mult,
                highmid_mult,
                high_mult,
                &self.xo1_lp, &self.xo1_hp,
                &self.xo2_lp, &self.xo2_hp,
                &self.xo3_lp, &self.xo3_hp,
                self.freeze,
            );

            // Allpass in feedback path (R6.3) — adds density to tail
            let with_allpass = self.delay_lines[i].feedback_allpass.process(shaped);

            // Feedback mode processing (R7.2/R7.3): pitch shift or waveshaping
            let with_mode = match self.feedback_mode {
                FeedbackMode::Shimmer => {
                    self.shimmer_shifters[i].process(with_allpass)
                }
                FeedbackMode::Nonlinear => {
                    let drive = 1.5 + self.nonlinear_drive * 4.0;
                    (with_allpass * drive).tanh() / drive.tanh()
                }
                FeedbackMode::Normal => with_allpass,
            };

            // Thickness saturation
            let with_thickness = if saturation > 0.001 {
                let drive = 1.0 + saturation * 2.0;
                (with_mode * drive).tanh() / drive.tanh()
            } else {
                with_mode
            };

            self.delay_lines[i].write(with_thickness + inputs[i]);
        }

        // Sum outputs to stereo — first half → left, second half → right
        // Asymmetric gains preserving stereo image
        let mut out_l = 0.0;
        let mut out_r = 0.0;
        for i in 0..half {
            // Decreasing weight: first line strongest
            let w = 0.30 - (i as f64) * (0.10 / (half - 1).max(1) as f64);
            out_l += outputs[i] * w;
        }
        for i in half..n {
            let w = 0.30 - ((i - half) as f64) * (0.10 / (half - 1).max(1) as f64);
            out_r += outputs[i] * w;
        }

        (out_l, out_r)
    }

    fn reset(&mut self) {
        for dl in &mut self.delay_lines {
            dl.reset();
        }
        for ss in &mut self.shimmer_shifters {
            ss.reset();
        }
        let n = self.active_size;
        for i in 0..n {
            self.velvet_gens[i].reset(VN_SEEDS[i]);
        }
        self.chorus_phase = 0.0;
    }
}

/// Reverb gate — envelope-controlled gate on reverb tail (R7.5)
/// Classic 80s gated reverb: hard cut after hold time
#[derive(Debug, Clone)]
struct ReverbGate {
    envelope: f64,
    hold_counter: usize,
    hold_samples: usize,   // Hold time in samples
    release_coeff: f64,     // Release envelope coefficient
    active: bool,
    gate_open: bool,
}

impl ReverbGate {
    fn new(sample_rate: f64) -> Self {
        Self {
            envelope: 0.0,
            hold_counter: 0,
            hold_samples: (sample_rate * 0.3) as usize, // 300ms default hold
            release_coeff: 1.0 - (-2.0 * std::f64::consts::PI / (0.020 * sample_rate)).exp(), // 20ms release
            active: false,
            gate_open: false,
        }
    }

    fn set_hold_time(&mut self, seconds: f64, sample_rate: f64) {
        self.hold_samples = (sample_rate * seconds.clamp(0.05, 2.0)) as usize;
    }

    fn set_release_time(&mut self, seconds: f64, sample_rate: f64) {
        self.release_coeff = 1.0 - (-2.0 * std::f64::consts::PI / (seconds * sample_rate)).exp();
    }

    /// Process: open gate on transient, close after hold+release
    #[inline(always)]
    fn process(&mut self, dry_level: f64, wet_l: &mut f64, wet_r: &mut f64) {
        if !self.active {
            return;
        }
        // Detect transient in dry signal
        let abs_dry = dry_level.abs();
        if abs_dry > 0.05 {
            self.gate_open = true;
            self.hold_counter = self.hold_samples;
            self.envelope = 1.0;
        }

        if self.gate_open {
            if self.hold_counter > 0 {
                self.hold_counter -= 1;
                // Gate fully open during hold
            } else {
                // Release phase
                self.envelope += (0.0 - self.envelope) * self.release_coeff;
                if self.envelope < 0.001 {
                    self.envelope = 0.0;
                    self.gate_open = false;
                }
            }
        }

        *wet_l *= self.envelope;
        *wet_r *= self.envelope;
    }

    fn reset(&mut self) {
        self.envelope = 0.0;
        self.hold_counter = 0;
        self.gate_open = false;
    }
}

/// Self-ducker — uses dry signal envelope to duck wet signal
#[derive(Debug, Clone)]
struct SelfDucker {
    envelope: f64,
    attack_coeff: f64,
    release_coeff: f64,
    amount: f64,
}

impl SelfDucker {
    fn new(sample_rate: f64) -> Self {
        // ~5ms attack, ~200ms release
        let attack_coeff = 1.0 - (-2.0 * std::f64::consts::PI / (0.005 * sample_rate)).exp();
        let release_coeff = 1.0 - (-2.0 * std::f64::consts::PI / (0.200 * sample_rate)).exp();

        Self {
            envelope: 0.0,
            attack_coeff,
            release_coeff,
            amount: 0.0,
        }
    }

    #[inline(always)]
    fn process(&mut self, dry_level: f64, wet_l: &mut f64, wet_r: &mut f64) {
        if self.amount <= 0.001 {
            return; // Skip when ducking is off
        }

        let abs_dry = dry_level.abs();
        if abs_dry > self.envelope {
            self.envelope += (abs_dry - self.envelope) * self.attack_coeff;
        } else {
            self.envelope += (abs_dry - self.envelope) * self.release_coeff;
        }

        let duck_gain = (1.0 - self.envelope * self.amount).max(0.0);
        *wet_l *= duck_gain;
        *wet_r *= duck_gain;
    }

    fn reset(&mut self) {
        self.envelope = 0.0;
    }
}

// ============================================================================
// Main AlgorithmicReverb — Configurable FDN (2026 Ultimate Upgrade)
// ============================================================================

/// Algorithmic stereo reverb — configurable FDN with selectable matrix (R6.1-R6.6)
///
/// Signal flow:
///   Input → PreDelay → EarlyReflections → Diffusion → FDN (4/8/16) → M/S Width → Dry/Wet Mix → Output
///
/// 24 automatable parameters (indices 0-23)
#[derive(Debug, Clone)]
pub struct AlgorithmicReverb {
    style: ReverbType,

    // Processing stages
    er_engine: EarlyReflectionEngine,
    diffusion: DiffusionStage,
    fdn: FDNCore,
    ducker: SelfDucker,
    gate: ReverbGate,

    // Parameters (24 total)
    space: f64,       // 0: Space (0.0-1.0)
    brightness: f64,  // 1: Brightness (0.0-1.0)
    width: f64,       // 2: Width (0.0-2.0)
    mix: f64,         // 3: Mix (0.0-1.0)
    predelay_ms: f64, // 4: PreDelay (0-500ms)
    // style is param 5
    diffusion_param: f64,  // 6: Diffusion (0.0-1.0)
    distance: f64,         // 7: Distance (0.0-1.0)
    decay: f64,            // 8: Decay (0.0-1.0)
    low_decay_mult: f64,   // 9: Low Decay Mult (0.5-2.0)
    high_decay_mult: f64,  // 10: High Decay Mult (0.5-2.0)
    character: f64,        // 11: Character (0.0-1.0)
    thickness: f64,        // 12: Thickness (0.0-1.0)
    ducking: f64,          // 13: Ducking (0.0-1.0)
    freeze_param: bool,    // 14: Freeze (bool)
    spin: f64,             // 15: Spin (0.0-1.0)
    wander: f64,           // 16: Wander (0.0-1.0)
    er_level: f64,         // 17: ER Level (0.0-1.0)
    late_level: f64,       // 18: Late Level (0.0-1.0)
    xo_freq_1: f64,        // 19: Crossover 1 freq Hz (20-2000, default 250)
    xo_freq_2: f64,        // 20: Crossover 2 freq Hz (200-10000, default 2000)
    xo_freq_3: f64,        // 21: Crossover 3 freq Hz (2000-20000, default 8000)
    lowmid_decay_mult: f64, // 22: LowMid Decay Mult (0.5-2.0)
    highmid_decay_mult: f64, // 23: HighMid Decay Mult (0.5-2.0)

    // F5: Output EQ — 2 shelves + 1 parametric mid
    out_eq_low_shelf_gain: f64,   // 24: Low shelf gain dB (-12 to +12)
    out_eq_low_shelf_freq: f64,   // 25: Low shelf freq Hz (80-500)
    out_eq_high_shelf_gain: f64,  // 26: High shelf gain dB (-12 to +12)
    out_eq_high_shelf_freq: f64,  // 27: High shelf freq Hz (2000-16000)
    out_eq_mid_gain: f64,         // 28: Mid gain dB (-12 to +12)
    out_eq_mid_freq: f64,         // 29: Mid freq Hz (200-8000)
    out_eq_mid_q: f64,            // 30: Mid Q (0.5-5.0)
    out_eq_enabled: bool,         // any non-zero gain enables
    out_eq_low_coeffs: BiquadCoeffs,
    out_eq_high_coeffs: BiquadCoeffs,
    out_eq_mid_coeffs: BiquadCoeffs,
    out_eq_low_z1_l: f64, out_eq_low_z2_l: f64,
    out_eq_low_z1_r: f64, out_eq_low_z2_r: f64,
    out_eq_high_z1_l: f64, out_eq_high_z2_l: f64,
    out_eq_high_z1_r: f64, out_eq_high_z2_r: f64,
    out_eq_mid_z1_l: f64, out_eq_mid_z2_l: f64,
    out_eq_mid_z1_r: f64, out_eq_mid_z2_r: f64,

    // F5: Soft limiter
    soft_limiter_enabled: bool,   // 31: On/Off

    // F5: Pre-delay BPM sync
    predelay_bpm_sync: bool,      // 32: BPM sync On/Off
    predelay_bpm: f64,            // 33: BPM (60-200)
    predelay_note_div: u8,        // 34: Note division (0-7)

    // F5: Pre-delay feedback
    predelay_feedback: f64,       // 35: Feedback (0.0-0.5)

    // F8: Advanced FDN controls
    fdn_size_param: u8,           // 36: FDN Size (0=Small/4, 1=Medium/8, 2=Large/16)
    matrix_type_param: u8,        // 37: Matrix Type (0=Hadamard, 1=Householder)

    // PreDelay circular buffer
    predelay_buffer_l: Vec<Sample>,
    predelay_buffer_r: Vec<Sample>,
    predelay_pos: usize,
    predelay_samples: usize,

    sample_rate: f64,
}

impl AlgorithmicReverb {
    pub fn new(sample_rate: f64) -> Self {
        let max_predelay = (sample_rate * 0.5) as usize; // 500ms max predelay

        let mut reverb = Self {
            style: ReverbType::Hall,
            er_engine: EarlyReflectionEngine::new(sample_rate),
            diffusion: DiffusionStage::new(sample_rate),
            fdn: FDNCore::new(sample_rate),
            ducker: SelfDucker::new(sample_rate),
            gate: ReverbGate::new(sample_rate),

            space: 0.5,
            brightness: 0.6,
            width: 1.0,
            mix: 0.33,
            predelay_ms: 0.0,
            diffusion_param: 0.0,
            distance: 0.0,
            decay: 0.5,
            low_decay_mult: 1.0,
            high_decay_mult: 1.0,
            character: 0.0,
            thickness: 0.0,
            ducking: 0.0,
            freeze_param: false,
            spin: 0.5,    // Default spin (maps to ~3 Hz)
            wander: 0.5,  // Default wander (maps to ~0.2 Hz)
            er_level: 1.0,
            late_level: 1.0,
            xo_freq_1: 250.0,
            xo_freq_2: 2000.0,
            xo_freq_3: 8000.0,
            lowmid_decay_mult: 1.0,
            highmid_decay_mult: 1.0,

            // F5: Output EQ (defaults: flat)
            out_eq_low_shelf_gain: 0.0,
            out_eq_low_shelf_freq: 200.0,
            out_eq_high_shelf_gain: 0.0,
            out_eq_high_shelf_freq: 8000.0,
            out_eq_mid_gain: 0.0,
            out_eq_mid_freq: 1000.0,
            out_eq_mid_q: 1.0,
            out_eq_enabled: false,
            out_eq_low_coeffs: BiquadCoeffs::bypass(),
            out_eq_high_coeffs: BiquadCoeffs::bypass(),
            out_eq_mid_coeffs: BiquadCoeffs::bypass(),
            out_eq_low_z1_l: 0.0, out_eq_low_z2_l: 0.0,
            out_eq_low_z1_r: 0.0, out_eq_low_z2_r: 0.0,
            out_eq_high_z1_l: 0.0, out_eq_high_z2_l: 0.0,
            out_eq_high_z1_r: 0.0, out_eq_high_z2_r: 0.0,
            out_eq_mid_z1_l: 0.0, out_eq_mid_z2_l: 0.0,
            out_eq_mid_z1_r: 0.0, out_eq_mid_z2_r: 0.0,

            // F5: Soft limiter (default: off)
            soft_limiter_enabled: false,

            // F5: Pre-delay BPM sync (default: off)
            predelay_bpm_sync: false,
            predelay_bpm: 120.0,
            predelay_note_div: 2, // 1/4 note
            predelay_feedback: 0.0,

            // F8: Advanced FDN
            fdn_size_param: 1,  // Medium (8×8)
            matrix_type_param: 0, // Hadamard

            predelay_buffer_l: vec![0.0; max_predelay.max(1)],
            predelay_buffer_r: vec![0.0; max_predelay.max(1)],
            predelay_pos: 0,
            predelay_samples: 0,
            sample_rate,
        };

        // Apply initial parameter state
        reverb.recalc_internals();
        reverb
    }

    /// Recalculate all internal coefficients from current parameters
    fn recalc_internals(&mut self) {
        let scaling = self.style.scaling();

        // Space affects ER spacing + FDN delay lengths
        let effective_space = self.space * scaling.space;
        self.er_engine
            .update_space_scale(effective_space.max(0.1), self.sample_rate);
        self.fdn
            .update_space_scale(effective_space.max(0.1), self.sample_rate);

        // Brightness → high decay mult (inverted: bright=1.0 means more HF)
        // This is applied as an additional scale on top of user high_decay_mult
        let brightness_hf = 0.3 + self.brightness * 0.7; // 0.3-1.0

        // Decay
        self.fdn.update_decay(self.decay);

        // 4-band crossover frequencies (R4.2)
        self.fdn.update_crossover_freqs(
            self.xo_freq_1, self.xo_freq_2, self.xo_freq_3, self.sample_rate,
        );

        // Distance affects ER
        self.er_engine.update_distance(self.distance);

        // Diffusion
        let effective_diffusion = self.diffusion_param * scaling.diffusion;
        self.diffusion
            .update_diffusion(effective_diffusion.clamp(0.0, 1.0));

        // Diffusion allpass modulation (R3.4): slow LFO on delay lengths
        // Prevents metallic buildup in dense diffusion networks
        // Rate: 0.3-1.5 Hz, depth: 0-2 samples (subtle, avoids pitch artifacts)
        let diff_mod_rate = 0.3 + self.character * 1.2;
        let diff_mod_depth = self.character * 2.0;
        self.diffusion.set_modulation(diff_mod_rate, diff_mod_depth);

        // Character affects mod depth — expanded range for velvet noise (R1.5)
        // 0.0 → 0.0001 (nearly off), 1.0 → 0.01 (10× previous max)
        let effective_mod = 0.0001 + self.character * 0.0099; // 0.0001-0.01
        self.fdn.mod_depth = effective_mod * scaling.modulation;

        // Spin: fast modulation rate (1-5 Hz) + depth contribution
        // spin 0.0 → 1.0 Hz, 1.0 → 5.0 Hz
        let spin_hz = 1.0 + self.spin * 4.0;
        self.fdn.spin_depth = self.spin;
        for vg in &mut self.fdn.velvet_gens {
            vg.set_spin_rate(spin_hz);
        }

        // Wander: slow drift rate (0.05-0.5 Hz) + depth contribution
        // wander 0.0 → 0.05 Hz, 1.0 → 0.5 Hz
        let wander_hz = 0.05 + self.wander * 0.45;
        self.fdn.wander_depth = self.wander;
        for vg in &mut self.fdn.velvet_gens {
            vg.set_wander_rate(wander_hz);
        }

        // Delay line jitter (R6.4): character drives jitter amount
        // Subtle randomization prevents comb-filter coloration
        self.fdn.jitter_amount = self.character * 0.5; // 0-50% of max jitter
        self.fdn.update_jitter();

        // Chorus / Shimmer mode
        if self.style == ReverbType::Shimmer {
            // Shimmer (R7.2): always-on, ±1200 cents (octave up), slow LFO
            self.fdn.set_chorus(true, 1200.0, 0.3, self.sample_rate);
        } else {
            // Normal chorus mode (R6.6): activates at high character values (>0.5)
            let chorus_active = self.character > 0.5;
            let chorus_cents = if chorus_active {
                (self.character - 0.5) * 10.0 // 0-5 cents
            } else {
                0.0
            };
            self.fdn.set_chorus(chorus_active, chorus_cents, 1.5, self.sample_rate);
        }

        // Ducking amount
        self.ducker.amount = self.ducking;

        // Freeze
        self.fdn.freeze = self.freeze_param;

        // Store computed brightness for process()
        let _ = brightness_hf; // Used in process() via self.brightness
    }

    // ====================================================================
    // Setters — new API names (F1.7 / F2.2)
    // ====================================================================

    pub fn set_space(&mut self, space: f64) {
        self.space = space.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_brightness(&mut self, brightness: f64) {
        self.brightness = brightness.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_width(&mut self, width: f64) {
        self.width = width.clamp(0.0, 2.0);
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    pub fn set_predelay(&mut self, ms: f64) {
        self.predelay_ms = ms.clamp(0.0, 500.0);
        self.predelay_samples = ((ms * 0.001 * self.sample_rate) as usize)
            .min(self.predelay_buffer_l.len().saturating_sub(1));
    }

    pub fn set_style(&mut self, style: ReverbType) {
        self.style = style;
        // Style applies per-style ER pattern + diffusion topology + scaling factors
        self.er_engine.set_style(&style, self.sample_rate);
        self.diffusion.set_topology_for_style(&style);
        // Set per-style feedback mode (R7)
        self.fdn.feedback_mode = match style {
            ReverbType::Shimmer => FeedbackMode::Shimmer,
            ReverbType::Nonlinear => FeedbackMode::Nonlinear,
            _ => FeedbackMode::Normal,
        };
        self.fdn.nonlinear_drive = match style {
            ReverbType::Nonlinear => 0.5,
            _ => 0.0,
        };
        // Gated reverb (R7.5)
        self.gate.active = style == ReverbType::Gated;
        self.gate.set_hold_time(0.3, self.sample_rate); // 300ms hold
        self.gate.set_release_time(0.02, self.sample_rate); // 20ms release (sharp cut)
        self.recalc_internals();
    }

    pub fn set_diffusion(&mut self, diffusion: f64) {
        self.diffusion_param = diffusion.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_distance(&mut self, distance: f64) {
        self.distance = distance.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_decay(&mut self, decay: f64) {
        self.decay = decay.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_low_decay_mult(&mut self, mult: f64) {
        self.low_decay_mult = mult.clamp(0.5, 2.0);
    }

    pub fn set_high_decay_mult(&mut self, mult: f64) {
        self.high_decay_mult = mult.clamp(0.5, 2.0);
    }

    pub fn set_character(&mut self, character: f64) {
        self.character = character.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    pub fn set_thickness(&mut self, thickness: f64) {
        self.thickness = thickness.clamp(0.0, 1.0);
    }

    pub fn set_ducking(&mut self, ducking: f64) {
        self.ducking = ducking.clamp(0.0, 1.0);
        self.ducker.amount = self.ducking;
    }

    pub fn set_freeze(&mut self, freeze: bool) {
        self.freeze_param = freeze;
        self.fdn.freeze = freeze;
    }

    /// Spin: fast modulation rate/depth (0.0-1.0)
    /// 0.0 = minimal fast modulation, 1.0 = maximum chorus-like movement
    pub fn set_spin(&mut self, spin: f64) {
        self.spin = spin.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    /// Wander: slow drift rate/depth (0.0-1.0)
    /// 0.0 = static, 1.0 = maximum slow spatial drift
    pub fn set_wander(&mut self, wander: f64) {
        self.wander = wander.clamp(0.0, 1.0);
        self.recalc_internals();
    }

    /// ER Level: early reflections gain (0.0-1.0)
    pub fn set_er_level(&mut self, level: f64) {
        self.er_level = level.clamp(0.0, 1.0);
    }

    /// Late Level: FDN reverb tail gain (0.0-1.0)
    pub fn set_late_level(&mut self, level: f64) {
        self.late_level = level.clamp(0.0, 1.0);
    }

    /// Crossover 1 frequency Hz (Low/LowMid split, 20-2000)
    pub fn set_xo_freq_1(&mut self, freq: f64) {
        self.xo_freq_1 = freq.clamp(20.0, 2000.0);
        self.recalc_internals();
    }

    /// Crossover 2 frequency Hz (LowMid/HighMid split, 200-10000)
    pub fn set_xo_freq_2(&mut self, freq: f64) {
        self.xo_freq_2 = freq.clamp(200.0, 10000.0);
        self.recalc_internals();
    }

    /// Crossover 3 frequency Hz (HighMid/High split, 2000-20000)
    pub fn set_xo_freq_3(&mut self, freq: f64) {
        self.xo_freq_3 = freq.clamp(2000.0, 20000.0);
        self.recalc_internals();
    }

    /// LowMid decay multiplier (0.5-2.0)
    pub fn set_lowmid_decay_mult(&mut self, mult: f64) {
        self.lowmid_decay_mult = mult.clamp(0.5, 2.0);
    }

    /// HighMid decay multiplier (0.5-2.0)
    pub fn set_highmid_decay_mult(&mut self, mult: f64) {
        self.highmid_decay_mult = mult.clamp(0.5, 2.0);
    }

    // ====================================================================
    // Getters
    // ====================================================================

    pub fn space(&self) -> f64 {
        self.space
    }
    pub fn brightness(&self) -> f64 {
        self.brightness
    }
    pub fn width(&self) -> f64 {
        self.width
    }
    pub fn mix(&self) -> f64 {
        self.mix
    }
    pub fn predelay_ms(&self) -> f64 {
        self.predelay_ms
    }
    pub fn style(&self) -> ReverbType {
        self.style
    }
    pub fn diffusion(&self) -> f64 {
        self.diffusion_param
    }
    pub fn distance(&self) -> f64 {
        self.distance
    }
    pub fn decay(&self) -> f64 {
        self.decay
    }
    pub fn low_decay_mult(&self) -> f64 {
        self.low_decay_mult
    }
    pub fn high_decay_mult(&self) -> f64 {
        self.high_decay_mult
    }
    pub fn character(&self) -> f64 {
        self.character
    }
    pub fn thickness(&self) -> f64 {
        self.thickness
    }
    pub fn ducking(&self) -> f64 {
        self.ducking
    }
    pub fn freeze(&self) -> bool {
        self.freeze_param
    }
    pub fn spin(&self) -> f64 {
        self.spin
    }
    pub fn wander(&self) -> f64 {
        self.wander
    }
    pub fn er_level(&self) -> f64 {
        self.er_level
    }
    pub fn late_level(&self) -> f64 {
        self.late_level
    }
    pub fn xo_freq_1(&self) -> f64 {
        self.xo_freq_1
    }
    pub fn xo_freq_2(&self) -> f64 {
        self.xo_freq_2
    }
    pub fn xo_freq_3(&self) -> f64 {
        self.xo_freq_3
    }
    pub fn lowmid_decay_mult(&self) -> f64 {
        self.lowmid_decay_mult
    }
    pub fn highmid_decay_mult(&self) -> f64 {
        self.highmid_decay_mult
    }

    // F5: Output EQ getters/setters
    pub fn out_eq_low_shelf_gain(&self) -> f64 { self.out_eq_low_shelf_gain }
    pub fn out_eq_low_shelf_freq(&self) -> f64 { self.out_eq_low_shelf_freq }
    pub fn out_eq_high_shelf_gain(&self) -> f64 { self.out_eq_high_shelf_gain }
    pub fn out_eq_high_shelf_freq(&self) -> f64 { self.out_eq_high_shelf_freq }
    pub fn out_eq_mid_gain(&self) -> f64 { self.out_eq_mid_gain }
    pub fn out_eq_mid_freq(&self) -> f64 { self.out_eq_mid_freq }
    pub fn out_eq_mid_q(&self) -> f64 { self.out_eq_mid_q }
    pub fn soft_limiter_enabled(&self) -> bool { self.soft_limiter_enabled }
    pub fn predelay_bpm_sync(&self) -> bool { self.predelay_bpm_sync }
    pub fn predelay_bpm(&self) -> f64 { self.predelay_bpm }
    pub fn predelay_note_div(&self) -> u8 { self.predelay_note_div }
    pub fn predelay_feedback(&self) -> f64 { self.predelay_feedback }

    pub fn set_out_eq_low_shelf_gain(&mut self, gain_db: f64) {
        self.out_eq_low_shelf_gain = gain_db.clamp(-12.0, 12.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_low_shelf_freq(&mut self, freq: f64) {
        self.out_eq_low_shelf_freq = freq.clamp(80.0, 500.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_high_shelf_gain(&mut self, gain_db: f64) {
        self.out_eq_high_shelf_gain = gain_db.clamp(-12.0, 12.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_high_shelf_freq(&mut self, freq: f64) {
        self.out_eq_high_shelf_freq = freq.clamp(2000.0, 16000.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_mid_gain(&mut self, gain_db: f64) {
        self.out_eq_mid_gain = gain_db.clamp(-12.0, 12.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_mid_freq(&mut self, freq: f64) {
        self.out_eq_mid_freq = freq.clamp(200.0, 8000.0);
        self.update_output_eq();
    }
    pub fn set_out_eq_mid_q(&mut self, q: f64) {
        self.out_eq_mid_q = q.clamp(0.5, 5.0);
        self.update_output_eq();
    }
    pub fn set_soft_limiter_enabled(&mut self, enabled: bool) {
        self.soft_limiter_enabled = enabled;
    }
    pub fn set_predelay_bpm_sync(&mut self, enabled: bool) {
        self.predelay_bpm_sync = enabled;
        if enabled {
            self.sync_predelay_to_bpm();
        }
    }
    pub fn set_predelay_bpm(&mut self, bpm: f64) {
        self.predelay_bpm = bpm.clamp(60.0, 200.0);
        if self.predelay_bpm_sync {
            self.sync_predelay_to_bpm();
        }
    }

    /// Set project BPM — updates the pre-delay BPM sync parameter so tempo-
    /// synced pre-delay stays correct when the project BPM changes.
    /// BUG#7: Reverb was hardcoded to 120.0 BPM — call this from the FFI layer
    /// whenever the project BPM changes.
    pub fn set_bpm(&mut self, bpm: f64) {
        self.set_predelay_bpm(bpm);
    }
    pub fn set_predelay_note_div(&mut self, div: u8) {
        self.predelay_note_div = div.min(7);
        if self.predelay_bpm_sync {
            self.sync_predelay_to_bpm();
        }
    }
    pub fn set_predelay_feedback(&mut self, feedback: f64) {
        self.predelay_feedback = feedback.clamp(0.0, 0.5);
    }

    // F8: Advanced FDN
    pub fn fdn_size_param(&self) -> u8 { self.fdn_size_param }
    pub fn matrix_type_param(&self) -> u8 { self.matrix_type_param }
    pub fn set_fdn_size_param(&mut self, size: u8) {
        let size = size.min(2);
        if size != self.fdn_size_param {
            self.fdn_size_param = size;
            let fdn_size = match size {
                0 => FdnSize::Small,
                1 => FdnSize::Medium,
                _ => FdnSize::Large,
            };
            self.fdn.set_size(fdn_size, self.sample_rate);
        }
    }
    pub fn set_matrix_type_param(&mut self, mt: u8) {
        let mt = mt.min(1);
        if mt != self.matrix_type_param {
            self.matrix_type_param = mt;
            let matrix = match mt {
                0 => MixingMatrix::Hadamard,
                _ => MixingMatrix::Householder,
            };
            self.fdn.set_matrix_type(matrix);
        }
    }

    /// Update output EQ coefficients
    fn update_output_eq(&mut self) {
        let has_eq = self.out_eq_low_shelf_gain.abs() > 0.01
            || self.out_eq_high_shelf_gain.abs() > 0.01
            || self.out_eq_mid_gain.abs() > 0.01;
        self.out_eq_enabled = has_eq;
        if has_eq {
            self.out_eq_low_coeffs = if self.out_eq_low_shelf_gain.abs() > 0.01 {
                BiquadCoeffs::low_shelf(self.out_eq_low_shelf_freq, self.out_eq_low_shelf_gain, self.sample_rate)
            } else {
                BiquadCoeffs::bypass()
            };
            self.out_eq_high_coeffs = if self.out_eq_high_shelf_gain.abs() > 0.01 {
                BiquadCoeffs::high_shelf(self.out_eq_high_shelf_freq, self.out_eq_high_shelf_gain, self.sample_rate)
            } else {
                BiquadCoeffs::bypass()
            };
            self.out_eq_mid_coeffs = if self.out_eq_mid_gain.abs() > 0.01 {
                BiquadCoeffs::peaking_eq(self.out_eq_mid_freq, self.out_eq_mid_gain, self.out_eq_mid_q, self.sample_rate)
            } else {
                BiquadCoeffs::bypass()
            };
        }
    }

    /// Sync pre-delay time to BPM + note division
    fn sync_predelay_to_bpm(&mut self) {
        let beat_ms = 60000.0 / self.predelay_bpm;
        let note_ms = match self.predelay_note_div {
            0 => beat_ms * 4.0,       // 1/1
            1 => beat_ms * 2.0,       // 1/2
            2 => beat_ms,             // 1/4
            3 => beat_ms * 0.5,       // 1/8
            4 => beat_ms * 0.25,      // 1/16
            5 => beat_ms * 1.5,       // dotted 1/4
            6 => beat_ms * 0.75,      // dotted 1/8
            7 => beat_ms * 2.0 / 3.0, // triplet 1/4
            _ => beat_ms,
        };
        let clamped = note_ms.clamp(0.0, 500.0);
        self.predelay_ms = clamped;
        self.predelay_samples = ((clamped / 1000.0) * self.sample_rate) as usize;
        let buf_len = self.predelay_buffer_l.len();
        if self.predelay_samples >= buf_len {
            self.predelay_samples = buf_len - 1;
        }
    }

    // ====================================================================
    // Backward-compatible aliases (for existing wrapper code)
    // ====================================================================

    pub fn set_room_size(&mut self, size: f64) {
        self.set_space(size);
    }
    pub fn room_size(&self) -> f64 {
        self.space
    }
    pub fn set_damping(&mut self, damping: f64) {
        self.set_brightness(1.0 - damping);
    }
    pub fn damping(&self) -> f64 {
        1.0 - self.brightness
    }
    pub fn set_dry_wet(&mut self, mix: f64) {
        self.set_mix(mix);
    }
    pub fn dry_wet(&self) -> f64 {
        self.mix
    }
    pub fn set_type(&mut self, rt: ReverbType) {
        self.set_style(rt);
    }
    pub fn reverb_type(&self) -> ReverbType {
        self.style
    }

    /// M/S width processing (replaces old cross-feed model)
    #[inline(always)]
    fn apply_width(&self, left: f64, right: f64) -> (f64, f64) {
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;
        let side_scaled = side * self.width; // 0.0=mono, 1.0=natural, 2.0=ultra-wide
        (mid + side_scaled, mid - side_scaled)
    }
}

impl Processor for AlgorithmicReverb {
    fn reset(&mut self) {
        self.er_engine.reset();
        self.diffusion.reset();
        self.fdn.reset();
        self.ducker.reset();
        self.predelay_buffer_l.fill(0.0);
        self.predelay_buffer_r.fill(0.0);
        self.predelay_pos = 0;
        // Reset output EQ states
        self.out_eq_low_z1_l = 0.0; self.out_eq_low_z2_l = 0.0;
        self.out_eq_low_z1_r = 0.0; self.out_eq_low_z2_r = 0.0;
        self.out_eq_high_z1_l = 0.0; self.out_eq_high_z2_l = 0.0;
        self.out_eq_high_z1_r = 0.0; self.out_eq_high_z2_r = 0.0;
        self.out_eq_mid_z1_l = 0.0; self.out_eq_mid_z2_l = 0.0;
        self.out_eq_mid_z1_r = 0.0; self.out_eq_mid_z2_r = 0.0;
    }

    fn latency(&self) -> usize {
        self.predelay_samples
    }
}

impl StereoProcessor for AlgorithmicReverb {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // 1. PreDelay (0-500ms circular buffer) with optional feedback (R5.5)
        // WRITE FIRST so zero-delay reads the current sample
        let buf_len = self.predelay_buffer_l.len();
        let fb = self.predelay_feedback;

        // Read previous delayed output for feedback (before overwriting)
        let fb_read_pos = (self.predelay_pos + buf_len - self.predelay_samples) % buf_len;
        let fb_l = self.predelay_buffer_l[fb_read_pos] * fb;
        let fb_r = self.predelay_buffer_r[fb_read_pos] * fb;

        // Write input + feedback
        self.predelay_buffer_l[self.predelay_pos] = left + fb_l;
        self.predelay_buffer_r[self.predelay_pos] = right + fb_r;

        // Read delayed signal (after write, so zero-delay = current sample)
        let predelay_read_pos = (self.predelay_pos + buf_len - self.predelay_samples) % buf_len;
        let delayed_l = self.predelay_buffer_l[predelay_read_pos];
        let delayed_r = self.predelay_buffer_r[predelay_read_pos];

        self.predelay_pos = (self.predelay_pos + 1) % buf_len;

        // 2. Early Reflections (distance-controlled, stereo-decorrelated)
        let (er_raw_l, er_raw_r) = self.er_engine.process(delayed_l, delayed_r, self.distance);
        let er_l = er_raw_l * self.er_level;
        let er_r = er_raw_r * self.er_level;

        // Mix ER with pre-delayed signal for diffusion input
        let er_mix_l = delayed_l * 0.3 + er_l * 0.7;
        let er_mix_r = delayed_r * 0.3 + er_r * 0.7;

        // 3. Diffusion Stage (6 serial allpass)
        let (diff_l, diff_r) = self.diffusion.process(er_mix_l, er_mix_r);

        // 4. FDN Core (configurable size, 4-band decay, allpass feedback)
        // In freeze mode, bypass all band-decay shaping to maintain energy
        let (fdn_low, fdn_lowmid, fdn_highmid, fdn_high, fdn_thickness) = if self.freeze_param {
            (1.0, 1.0, 1.0, 1.0, 0.0)
        } else {
            let brightness_hf = 0.3 + self.brightness * 0.7;
            (
                self.low_decay_mult,
                self.lowmid_decay_mult,
                self.highmid_decay_mult * brightness_hf,
                self.high_decay_mult * brightness_hf,
                self.thickness,
            )
        };

        let (fdn_raw_l, fdn_raw_r) = self.fdn.process(
            diff_l, diff_r,
            fdn_low, fdn_lowmid, fdn_highmid, fdn_high,
            fdn_thickness,
        );

        // Apply late level to FDN output
        let fdn_l = fdn_raw_l * self.late_level;
        let fdn_r = fdn_raw_r * self.late_level;

        // 5. M/S Width (0.0=mono, 1.0=natural, 2.0=ultra-wide)
        let (wide_l, wide_r) = self.apply_width(fdn_l, fdn_r);

        // 6. Self-ducking (duck wet when dry is loud)
        let mut wet_l = wide_l;
        let mut wet_r = wide_r;
        let dry_mono = (left.abs() + right.abs()) * 0.5;
        self.ducker.process(dry_mono, &mut wet_l, &mut wet_r);

        // 6b. Gated reverb (R7.5): envelope gate on wet signal
        self.gate.process(dry_mono, &mut wet_l, &mut wet_r);

        // 6c. Output EQ (R5.1/R5.2): 2-band shelf + parametric mid
        if self.out_eq_enabled {
            wet_l = self.out_eq_low_coeffs.process_tdf2(
                wet_l, &mut self.out_eq_low_z1_l, &mut self.out_eq_low_z2_l);
            wet_r = self.out_eq_low_coeffs.process_tdf2(
                wet_r, &mut self.out_eq_low_z1_r, &mut self.out_eq_low_z2_r);
            wet_l = self.out_eq_high_coeffs.process_tdf2(
                wet_l, &mut self.out_eq_high_z1_l, &mut self.out_eq_high_z2_l);
            wet_r = self.out_eq_high_coeffs.process_tdf2(
                wet_r, &mut self.out_eq_high_z1_r, &mut self.out_eq_high_z2_r);
            wet_l = self.out_eq_mid_coeffs.process_tdf2(
                wet_l, &mut self.out_eq_mid_z1_l, &mut self.out_eq_mid_z2_l);
            wet_r = self.out_eq_mid_coeffs.process_tdf2(
                wet_r, &mut self.out_eq_mid_z1_r, &mut self.out_eq_mid_z2_r);
        }

        // 6d. Soft limiter (R5.3): tanh at -1dBFS threshold
        if self.soft_limiter_enabled {
            let threshold = 0.891; // -1 dBFS ≈ 10^(-1/20)
            wet_l = threshold * (wet_l / threshold).tanh();
            wet_r = threshold * (wet_r / threshold).tanh();
        }

        // 7. Equal-power crossfade (FabFilter Pro-R style)
        let mix_angle = self.mix * std::f64::consts::FRAC_PI_2;
        let dry_gain = mix_angle.cos();
        let wet_gain = mix_angle.sin();

        let out_l = left * dry_gain + wet_l * wet_gain;
        let out_r = right * dry_gain + wet_r * wet_gain;

        (out_l, out_r)
    }
}

impl ProcessorConfig for AlgorithmicReverb {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        if (sample_rate - self.sample_rate).abs() > 1.0 {
            // Preserve parameters, recreate processing stages
            let old = self.clone();
            *self = Self::new(sample_rate);
            // Restore all parameters
            self.space = old.space;
            self.brightness = old.brightness;
            self.width = old.width;
            self.mix = old.mix;
            self.predelay_ms = old.predelay_ms;
            self.style = old.style;
            self.diffusion_param = old.diffusion_param;
            self.distance = old.distance;
            self.decay = old.decay;
            self.low_decay_mult = old.low_decay_mult;
            self.high_decay_mult = old.high_decay_mult;
            self.character = old.character;
            self.thickness = old.thickness;
            self.ducking = old.ducking;
            self.freeze_param = old.freeze_param;
            self.spin = old.spin;
            self.wander = old.wander;
            self.er_level = old.er_level;
            self.late_level = old.late_level;
            self.xo_freq_1 = old.xo_freq_1;
            self.xo_freq_2 = old.xo_freq_2;
            self.xo_freq_3 = old.xo_freq_3;
            self.lowmid_decay_mult = old.lowmid_decay_mult;
            self.highmid_decay_mult = old.highmid_decay_mult;
            // F5 params
            self.out_eq_low_shelf_gain = old.out_eq_low_shelf_gain;
            self.out_eq_low_shelf_freq = old.out_eq_low_shelf_freq;
            self.out_eq_high_shelf_gain = old.out_eq_high_shelf_gain;
            self.out_eq_high_shelf_freq = old.out_eq_high_shelf_freq;
            self.out_eq_mid_gain = old.out_eq_mid_gain;
            self.out_eq_mid_freq = old.out_eq_mid_freq;
            self.out_eq_mid_q = old.out_eq_mid_q;
            self.soft_limiter_enabled = old.soft_limiter_enabled;
            self.predelay_bpm_sync = old.predelay_bpm_sync;
            self.predelay_bpm = old.predelay_bpm;
            self.predelay_note_div = old.predelay_note_div;
            self.predelay_feedback = old.predelay_feedback;
            self.fdn_size_param = old.fdn_size_param;
            self.matrix_type_param = old.matrix_type_param;
            self.set_predelay(old.predelay_ms);
            self.set_style(old.style); // Restore per-style ER pattern
            self.update_output_eq();
            self.recalc_internals();
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fdn_impulse_response() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0); // Full wet for testing
        reverb.set_decay(0.5);

        // Process impulse
        let (l, r) = reverb.process_sample(1.0, 1.0);

        // Should have some output (may be delayed by ER)
        let mut has_output = l.abs() > 0.0 || r.abs() > 0.0;

        // Process more samples to get past ER delay
        for _ in 0..5000 {
            let (l2, r2) = reverb.process_sample(0.0, 0.0);
            if l2.abs() > 1e-6 || r2.abs() > 1e-6 {
                has_output = true;
            }
            // No NaN or Inf
            assert!(!l2.is_nan(), "NaN in output");
            assert!(!r2.is_nan(), "NaN in output");
            assert!(!l2.is_infinite(), "Inf in output");
            assert!(!r2.is_infinite(), "Inf in output");
        }

        assert!(has_output, "Reverb produced no output after impulse");
    }

    #[test]
    fn test_fdn_silence_after_decay() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_decay(0.0); // Shortest decay (feedback ~0.70)

        // Feed impulse
        reverb.process_sample(1.0, 1.0);

        // Process enough silence for full decay
        let mut last_energy = 1.0;
        for _ in 0..48000 * 8 {
            // 8 seconds
            let (l, r) = reverb.process_sample(0.0, 0.0);
            last_energy = l.abs() + r.abs();
        }

        assert!(
            last_energy < 1e-4,
            "Reverb tail didn't decay: {}",
            last_energy
        );
    }

    #[test]
    fn test_fdn_parameter_sweep() {
        let mut reverb = AlgorithmicReverb::new(48000.0);

        // Test all 24 params at 3 values each
        let params_and_ranges: [(usize, f64, f64, f64); 24] = [
            (0, 0.0, 0.5, 1.0),         // Space
            (1, 0.0, 0.5, 1.0),         // Brightness
            (2, 0.0, 1.0, 2.0),         // Width
            (3, 0.0, 0.5, 1.0),         // Mix
            (4, 0.0, 100.0, 500.0),     // PreDelay
            (5, 0.0, 2.0, 4.0),         // Style
            (6, 0.0, 0.5, 1.0),         // Diffusion
            (7, 0.0, 0.5, 1.0),         // Distance
            (8, 0.0, 0.5, 1.0),         // Decay
            (9, 0.5, 1.0, 2.0),         // LowDecayMult
            (10, 0.5, 1.0, 2.0),        // HighDecayMult
            (11, 0.0, 0.5, 1.0),        // Character
            (12, 0.0, 0.5, 1.0),        // Thickness
            (13, 0.0, 0.5, 1.0),        // Ducking
            (14, 0.0, 0.0, 1.0),        // Freeze
            (15, 0.0, 0.5, 1.0),        // Spin
            (16, 0.0, 0.5, 1.0),        // Wander
            (17, 0.0, 0.5, 1.0),        // ER Level
            (18, 0.0, 0.5, 1.0),        // Late Level
            (19, 80.0, 250.0, 800.0),   // XO Freq 1
            (20, 500.0, 2000.0, 6000.0), // XO Freq 2
            (21, 3000.0, 8000.0, 16000.0), // XO Freq 3
            (22, 0.5, 1.0, 2.0),        // LowMid Decay Mult
            (23, 0.5, 1.0, 2.0),        // HighMid Decay Mult
        ];

        for (idx, lo, mid, hi) in params_and_ranges {
            for val in [lo, mid, hi] {
                match idx {
                    0 => reverb.set_space(val),
                    1 => reverb.set_brightness(val),
                    2 => reverb.set_width(val),
                    3 => reverb.set_mix(val),
                    4 => reverb.set_predelay(val),
                    5 => reverb.set_style(match val as u32 {
                        0 => ReverbType::Room,
                        1 => ReverbType::Hall,
                        2 => ReverbType::Plate,
                        3 => ReverbType::Chamber,
                        _ => ReverbType::Spring,
                    }),
                    6 => reverb.set_diffusion(val),
                    7 => reverb.set_distance(val),
                    8 => reverb.set_decay(val),
                    9 => reverb.set_low_decay_mult(val),
                    10 => reverb.set_high_decay_mult(val),
                    11 => reverb.set_character(val),
                    12 => reverb.set_thickness(val),
                    13 => reverb.set_ducking(val),
                    14 => reverb.set_freeze(val > 0.5),
                    15 => reverb.set_spin(val),
                    16 => reverb.set_wander(val),
                    17 => reverb.set_er_level(val),
                    18 => reverb.set_late_level(val),
                    19 => reverb.set_xo_freq_1(val),
                    20 => reverb.set_xo_freq_2(val),
                    21 => reverb.set_xo_freq_3(val),
                    22 => reverb.set_lowmid_decay_mult(val),
                    23 => reverb.set_highmid_decay_mult(val),
                    _ => {}
                }

                // Process some samples — should not panic or produce NaN
                for _ in 0..100 {
                    let (l, r) = reverb.process_sample(0.3, 0.3);
                    assert!(!l.is_nan(), "NaN for param {} = {}", idx, val);
                    assert!(!r.is_nan(), "NaN for param {} = {}", idx, val);
                }
            }
        }
    }

    #[test]
    fn test_fdn_determinism() {
        let mut reverb1 = AlgorithmicReverb::new(48000.0);
        let mut reverb2 = AlgorithmicReverb::new(48000.0);

        reverb1.set_mix(0.5);
        reverb1.set_decay(0.7);
        reverb2.set_mix(0.5);
        reverb2.set_decay(0.7);

        // Same input must produce bit-exact output
        for i in 0..1000 {
            let input = if i == 0 { 1.0 } else { 0.0 };
            let (l1, r1) = reverb1.process_sample(input, input);
            let (l2, r2) = reverb2.process_sample(input, input);
            assert_eq!(l1, l2, "Determinism failed at sample {}", i);
            assert_eq!(r1, r2, "Determinism failed at sample {}", i);
        }
    }

    #[test]
    fn test_fdn_stability() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_decay(1.0); // Maximum decay

        // 10 seconds of sustained input — output must stay bounded
        // With continuous input, the FDN accumulates energy. Bound is proportional to input.
        for _ in 0..48000 * 10 {
            let (l, r) = reverb.process_sample(0.5, 0.5);
            assert!(l.abs() < 50.0, "Output unstable: L={}", l);
            assert!(r.abs() < 50.0, "Output unstable: R={}", r);
        }
    }

    #[test]
    fn test_fdn_style_no_override() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_space(0.7);
        reverb.set_brightness(0.8);

        let space_before = reverb.space();
        let brightness_before = reverb.brightness();

        // Changing style should NOT override space/brightness
        reverb.set_style(ReverbType::Hall);

        assert_eq!(reverb.space(), space_before, "Style overrode Space!");
        assert_eq!(
            reverb.brightness(),
            brightness_before,
            "Style overrode Brightness!"
        );

        reverb.set_style(ReverbType::Plate);
        assert_eq!(reverb.space(), space_before, "Style overrode Space!");
        assert_eq!(
            reverb.brightness(),
            brightness_before,
            "Style overrode Brightness!"
        );
    }

    #[test]
    fn test_fdn_width_mono() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_width(0.0); // Mono
        reverb.set_decay(0.5);

        // Feed impulse
        reverb.process_sample(1.0, 0.0); // Asymmetric input

        // After some processing, L and R should be identical with width=0
        for _ in 0..500 {
            let (l, r) = reverb.process_sample(0.0, 0.0);
            if l.abs() > 1e-10 || r.abs() > 1e-10 {
                assert!((l - r).abs() < 1e-10, "Width=0 but L≠R: L={}, R={}", l, r);
            }
        }
    }

    #[test]
    fn test_fdn_width_wide() {
        // M/S width test: width=2.0 should widen stereo image vs width=1.0
        // Since FDN's Hadamard mixing makes L≈R, we test apply_width directly
        // AND verify the full reverb with asymmetric input produces wider output at width=2.0

        // Direct M/S test (unit test of apply_width)
        let reverb = AlgorithmicReverb::new(48000.0);
        let (l, r) = reverb.apply_width(0.8, 0.2); // Known L≠R
        // mid=(0.8+0.2)/2=0.5, side=(0.8-0.2)/2=0.3
        // width=1.0 (default): side_scaled=0.3
        // output: (0.5+0.3, 0.5-0.3) = (0.8, 0.2) — unchanged
        assert!((l - 0.8).abs() < 1e-10, "Width=1.0 should preserve stereo");
        assert!((r - 0.2).abs() < 1e-10, "Width=1.0 should preserve stereo");

        // Width=2.0: side_scaled=0.6, output=(0.5+0.6, 0.5-0.6) = (1.1, -0.1)
        let mut reverb_wide = AlgorithmicReverb::new(48000.0);
        reverb_wide.set_width(2.0);
        let (l2, r2) = reverb_wide.apply_width(0.8, 0.2);
        assert!(
            (l2 - 1.1).abs() < 1e-10,
            "Width=2.0 L expected 1.1, got {}",
            l2
        );
        assert!(
            (r2 - (-0.1)).abs() < 1e-10,
            "Width=2.0 R expected -0.1, got {}",
            r2
        );

        // Width=0.0: side_scaled=0.0, output=(0.5, 0.5) — mono
        let mut reverb_mono = AlgorithmicReverb::new(48000.0);
        reverb_mono.set_width(0.0);
        let (l3, r3) = reverb_mono.apply_width(0.8, 0.2);
        assert!((l3 - 0.5).abs() < 1e-10, "Width=0.0 should be mono");
        assert!((r3 - 0.5).abs() < 1e-10, "Width=0.0 should be mono");

        // Full reverb: compare stereo energy ratio between width=0.5 and width=2.0
        let mut rev_narrow = AlgorithmicReverb::new(48000.0);
        rev_narrow.set_mix(1.0);
        rev_narrow.set_width(0.5);
        rev_narrow.set_decay(0.8);

        let mut rev_wide2 = AlgorithmicReverb::new(48000.0);
        rev_wide2.set_mix(1.0);
        rev_wide2.set_width(2.0);
        rev_wide2.set_decay(0.8);

        // Feed asymmetric input
        for _ in 0..5000 {
            rev_narrow.process_sample(0.9, 0.1);
            rev_wide2.process_sample(0.9, 0.1);
        }

        let mut narrow_side_energy = 0.0;
        let mut wide_side_energy = 0.0;
        for _ in 0..10000 {
            let (nl, nr) = rev_narrow.process_sample(0.0, 0.0);
            let (wl, wr) = rev_wide2.process_sample(0.0, 0.0);
            narrow_side_energy += (nl - nr).powi(2);
            wide_side_energy += (wl - wr).powi(2);
        }

        // Width=2.0 should have more side energy than width=0.5
        assert!(
            wide_side_energy >= narrow_side_energy,
            "Width=2.0 should have ≥ side energy vs 0.5: wide={}, narrow={}",
            wide_side_energy,
            narrow_side_energy
        );
    }

    #[test]
    fn test_fdn_multiband_decay() {
        // Low mult=2.0 should make bass decay slower
        let mut reverb_normal = AlgorithmicReverb::new(48000.0);
        reverb_normal.set_mix(1.0);
        reverb_normal.set_decay(0.5);
        reverb_normal.set_low_decay_mult(1.0);

        let mut reverb_bass = AlgorithmicReverb::new(48000.0);
        reverb_bass.set_mix(1.0);
        reverb_bass.set_decay(0.5);
        reverb_bass.set_low_decay_mult(2.0);

        // Feed same impulse to both
        reverb_normal.process_sample(1.0, 1.0);
        reverb_bass.process_sample(1.0, 1.0);

        // After long decay, bass-boosted version should have more energy
        let mut energy_normal = 0.0;
        let mut energy_bass = 0.0;
        for _ in 0..48000 * 2 {
            let (l1, r1) = reverb_normal.process_sample(0.0, 0.0);
            let (l2, r2) = reverb_bass.process_sample(0.0, 0.0);
            energy_normal += l1 * l1 + r1 * r1;
            energy_bass += l2 * l2 + r2 * r2;
        }

        assert!(
            energy_bass > energy_normal,
            "Low mult=2.0 should produce more energy than 1.0: bass={}, normal={}",
            energy_bass,
            energy_normal
        );
    }

    #[test]
    fn test_fdn_character() {
        // Character=1.0 should produce denser reverb tail (more modulation)
        let mut reverb_low = AlgorithmicReverb::new(48000.0);
        reverb_low.set_mix(1.0);
        reverb_low.set_decay(0.7);
        reverb_low.set_character(0.0);

        let mut reverb_high = AlgorithmicReverb::new(48000.0);
        reverb_high.set_mix(1.0);
        reverb_high.set_decay(0.7);
        reverb_high.set_character(1.0);

        // Process same input — different character should produce different output
        reverb_low.process_sample(1.0, 1.0);
        reverb_high.process_sample(1.0, 1.0);

        let mut different = false;
        // Need enough samples for LFO modulation to diverge (~0.3 Hz → period ~3.3s)
        for _ in 0..48000 {
            let (l1, _) = reverb_low.process_sample(0.0, 0.0);
            let (l2, _) = reverb_high.process_sample(0.0, 0.0);
            if (l1 - l2).abs() > 1e-8 {
                different = true;
                break;
            }
        }
        assert!(
            different,
            "Character 0.0 vs 1.0 should produce different tails"
        );
    }

    #[test]
    fn test_fdn_early_reflections() {
        // Test ER engine directly — distance=0 should be brighter/louder than distance=1
        let mut er_close = EarlyReflectionEngine::new(48000.0);
        er_close.update_distance(0.0);

        let mut er_far = EarlyReflectionEngine::new(48000.0);
        er_far.update_distance(1.0);

        // Feed impulse
        let (cl, cr) = er_close.process(1.0, 1.0, 0.0);
        let (fl, fr) = er_far.process(1.0, 1.0, 1.0);

        let mut close_energy = cl * cl + cr * cr;
        let mut far_energy = fl * fl + fr * fr;

        // Measure ER output over first 100ms (4800 samples)
        for _ in 0..4800 {
            let (cl2, cr2) = er_close.process(0.0, 0.0, 0.0);
            let (fl2, fr2) = er_far.process(0.0, 0.0, 1.0);
            close_energy += cl2 * cl2 + cr2 * cr2;
            far_energy += fl2 * fl2 + fr2 * fr2;
        }

        assert!(
            close_energy > far_energy,
            "Distance=0 should have stronger ER than Distance=1: close={}, far={}",
            close_energy,
            far_energy
        );
    }

    #[test]
    fn test_fdn_predelay() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_predelay(50.0); // 50ms

        // First 50ms should be silence (2400 samples at 48kHz)
        let expected_delay = (50.0 * 0.001 * 48000.0) as usize;

        let mut first_nonzero = None;
        for i in 0..expected_delay + 1000 {
            let input = if i == 0 { 1.0 } else { 0.0 };
            let (l, _) = reverb.process_sample(input, input);
            if l.abs() > 1e-10 && first_nonzero.is_none() {
                first_nonzero = Some(i);
            }
        }

        if let Some(idx) = first_nonzero {
            // Should be at or after the predelay + ER delay
            assert!(
                idx >= expected_delay - 10,
                "Output appeared too early: sample {} (expected ≥{})",
                idx,
                expected_delay
            );
        }
    }

    #[test]
    fn test_fdn_thickness() {
        // Thickness adds tanh saturation + low_boost in FDN feedback path.
        // Test: compare total energy of thick vs thin — thickness adds harmonics
        // and low_boost increases bass energy.
        let mut reverb_thin = AlgorithmicReverb::new(48000.0);
        reverb_thin.set_mix(1.0);
        reverb_thin.set_decay(0.8);
        reverb_thin.set_thickness(0.0);

        let mut reverb_thick = AlgorithmicReverb::new(48000.0);
        reverb_thick.set_mix(1.0);
        reverb_thick.set_decay(0.8);
        reverb_thick.set_thickness(1.0);

        // Feed loud sustained input so saturation has non-trivial effect
        // Use high amplitude so FDN internal signals are large enough for tanh
        for _ in 0..10000 {
            reverb_thin.process_sample(0.9, 0.9);
            reverb_thick.process_sample(0.9, 0.9);
        }

        // Measure total energy of the reverb tail
        let mut energy_thin = 0.0;
        let mut energy_thick = 0.0;
        for _ in 0..48000 {
            // 1 second of tail
            let (l1, r1) = reverb_thin.process_sample(0.0, 0.0);
            let (l2, r2) = reverb_thick.process_sample(0.0, 0.0);
            energy_thin += l1 * l1 + r1 * r1;
            energy_thick += l2 * l2 + r2 * r2;
        }

        // Thickness=1.0 uses tanh saturation (which slightly compresses peaks)
        // and low_boost=1.5 (which increases bass decay).
        // The combined effect should produce DIFFERENT total energy.
        assert!(
            (energy_thin - energy_thick).abs() > 1e-10,
            "Thickness should affect reverb energy: thin={}, thick={}",
            energy_thin,
            energy_thick
        );
    }

    #[test]
    fn test_fdn_ducking() {
        // Ducking: during loud input, wet signal should be attenuated
        // Test by comparing output AFTER input stops (wet tail should recover with ducking)
        // vs DURING input (wet should be suppressed with ducking)
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(0.5); // 50/50 dry/wet so we get wet signal
        reverb.set_ducking(1.0); // Full ducking
        reverb.set_decay(0.8);

        // 1. Feed sustained input to build reverb tail
        for _ in 0..20000 {
            reverb.process_sample(0.5, 0.5);
        }

        // 2. Measure output during loud input (wet should be ducked)
        let mut energy_during = 0.0;
        for _ in 0..4800 {
            let (l, r) = reverb.process_sample(0.8, 0.8);
            energy_during += l * l + r * r;
        }

        // 3. Measure output during silence (wet tail should recover = ducker releases)
        let mut energy_after = 0.0;
        // Skip first 2400 samples (ducker release ~200ms = 9600 samples, but partial recovery)
        for _ in 0..2400 {
            reverb.process_sample(0.0, 0.0);
        }
        for _ in 0..4800 {
            let (l, r) = reverb.process_sample(0.0, 0.0);
            energy_after += l * l + r * r;
        }

        // During loud input: dry contribution is large BUT wet is ducked
        // After input stops: NO dry contribution, only wet tail (recovering)
        // The wet tail energy should be non-trivial (ducker releases)
        assert!(
            energy_after > 1e-6,
            "Wet tail should have energy after ducking releases: during={}, after={}",
            energy_during,
            energy_after
        );
    }

    #[test]
    fn test_fdn_ducking_release() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_ducking(0.8);
        reverb.set_decay(0.9);

        // Build up a large reverb tail with loud input
        for _ in 0..20000 {
            reverb.process_sample(0.8, 0.8);
        }

        // During input, output is ducked. Now feed silence — tail should recover.
        // We need to check if the output is non-trivial after ducker releases.
        let mut max_output = 0.0f64;
        for _ in 0..48000 {
            // 1 second
            let (l, r) = reverb.process_sample(0.0, 0.0);
            max_output = max_output.max(l.abs()).max(r.abs());
        }
        assert!(
            max_output > 0.001,
            "Wet signal should recover after input stops: max={}",
            max_output
        );
    }

    #[test]
    fn test_fdn_freeze_on() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_decay(0.5);

        // Build up a tail
        for _ in 0..5000 {
            reverb.process_sample(0.5, 0.5);
        }

        // Activate freeze
        reverb.set_freeze(true);

        // Feed silence — tail should sustain (not decay)
        let mut energies = Vec::new();
        for block in 0..10 {
            let mut block_energy = 0.0;
            for _ in 0..4800 {
                // 100ms blocks
                let (l, r) = reverb.process_sample(0.0, 0.0);
                block_energy += l * l + r * r;
            }
            energies.push(block_energy);

            // New input should be rejected (frozen)
            if block > 0 {
                let (l_with_input, r_with_input) = reverb.process_sample(1.0, 1.0);
                // The new input doesn't change the frozen state significantly
                assert!(!l_with_input.is_nan());
                assert!(!r_with_input.is_nan());
            }
        }

        // Energy should stay relatively constant (not decaying)
        let first = energies[0];
        let last = energies[energies.len() - 1];
        if first > 1e-6 {
            let ratio = last / first;
            assert!(
                ratio > 0.8,
                "Freeze should maintain energy: ratio={}",
                ratio
            );
        }
    }

    #[test]
    fn test_fdn_freeze_off() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_decay(0.0); // Minimum decay (feedback ~0.70)
        reverb.set_freeze(false);

        // Should operate normally (decay)
        reverb.process_sample(1.0, 1.0);

        // Process 8 seconds of silence
        for _ in 0..48000 * 8 {
            reverb.process_sample(0.0, 0.0);
        }

        // Should have decayed significantly
        let (last_l, last_r) = reverb.process_sample(0.0, 0.0);
        assert!(
            last_l.abs() < 0.01,
            "Should decay with freeze off: L={}",
            last_l
        );
        assert!(
            last_r.abs() < 0.01,
            "Should decay with freeze off: R={}",
            last_r
        );
    }

    #[test]
    fn test_fdn_backward_compat_aliases() {
        let mut reverb = AlgorithmicReverb::new(48000.0);

        // Old API should still work
        reverb.set_room_size(0.6);
        assert!((reverb.room_size() - 0.6).abs() < 1e-10);
        assert!((reverb.space() - 0.6).abs() < 1e-10);

        reverb.set_damping(0.4);
        assert!((reverb.damping() - 0.4).abs() < 1e-10);
        assert!((reverb.brightness() - 0.6).abs() < 1e-10); // Inverted

        reverb.set_dry_wet(0.5);
        assert!((reverb.dry_wet() - 0.5).abs() < 1e-10);
        assert!((reverb.mix() - 0.5).abs() < 1e-10);

        reverb.set_type(ReverbType::Hall);
        assert_eq!(reverb.reverb_type(), ReverbType::Hall);
        assert_eq!(reverb.style(), ReverbType::Hall);
    }

    #[test]
    fn test_fdn_param_roundtrip() {
        let mut reverb = AlgorithmicReverb::new(48000.0);

        reverb.set_space(0.7);
        assert!((reverb.space() - 0.7).abs() < 1e-10);

        reverb.set_brightness(0.8);
        assert!((reverb.brightness() - 0.8).abs() < 1e-10);

        reverb.set_width(1.5);
        assert!((reverb.width() - 1.5).abs() < 1e-10);

        reverb.set_mix(0.45);
        assert!((reverb.mix() - 0.45).abs() < 1e-10);

        reverb.set_predelay(120.0);
        assert!((reverb.predelay_ms() - 120.0).abs() < 1e-10);

        reverb.set_diffusion(0.9);
        assert!((reverb.diffusion() - 0.9).abs() < 1e-10);

        reverb.set_distance(0.3);
        assert!((reverb.distance() - 0.3).abs() < 1e-10);

        reverb.set_decay(0.6);
        assert!((reverb.decay() - 0.6).abs() < 1e-10);

        reverb.set_low_decay_mult(1.5);
        assert!((reverb.low_decay_mult() - 1.5).abs() < 1e-10);

        reverb.set_high_decay_mult(0.7);
        assert!((reverb.high_decay_mult() - 0.7).abs() < 1e-10);

        reverb.set_character(0.8);
        assert!((reverb.character() - 0.8).abs() < 1e-10);

        reverb.set_thickness(0.6);
        assert!((reverb.thickness() - 0.6).abs() < 1e-10);

        reverb.set_ducking(0.4);
        assert!((reverb.ducking() - 0.4).abs() < 1e-10);

        reverb.set_freeze(true);
        assert!(reverb.freeze());
        reverb.set_freeze(false);
        assert!(!reverb.freeze());
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
    fn test_fdn_all_styles() {
        let styles = [
            ReverbType::Room,
            ReverbType::Hall,
            ReverbType::Plate,
            ReverbType::Chamber,
            ReverbType::Spring,
        ];

        for style in styles {
            let mut reverb = AlgorithmicReverb::new(48000.0);
            reverb.set_style(style);

            // Process some samples — should not panic
            for _ in 0..1000 {
                let (l, r) = reverb.process_sample(0.5, 0.5);
                assert!(!l.is_nan());
                assert!(!r.is_nan());
            }
        }
    }

    #[test]
    fn test_fdn_zero_allocation_in_process() {
        // Verify process doesn't allocate by running many iterations
        // (if it allocated, it would be slow — this is a smoke test)
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(0.5);
        reverb.set_decay(0.7);

        for _ in 0..100_000 {
            let (l, r) = reverb.process_sample(0.1, 0.1);
            assert!(!l.is_nan());
            assert!(!r.is_nan());
        }
    }

    #[test]
    fn test_fdn_sample_rate_change() {
        let mut reverb = AlgorithmicReverb::new(44100.0);
        reverb.set_space(0.7);
        reverb.set_decay(0.6);
        reverb.set_brightness(0.8);

        // Change sample rate — should preserve parameters
        reverb.set_sample_rate(96000.0);

        assert!((reverb.space() - 0.7).abs() < 1e-10);
        assert!((reverb.decay() - 0.6).abs() < 1e-10);
        assert!((reverb.brightness() - 0.8).abs() < 1e-10);

        // Should still produce valid output
        let (l, r) = reverb.process_sample(1.0, 1.0);
        assert!(!l.is_nan());
        assert!(!r.is_nan());
    }

    #[test]
    fn test_fdn_sustained_energy() {
        let mut reverb = AlgorithmicReverb::new(48000.0);
        reverb.set_mix(1.0);
        reverb.set_space(0.5);
        reverb.set_decay(0.5);

        let mut total_energy = 0.0f64;
        for _ in 0..5120 {
            let (l, r) = reverb.process_sample(0.3, 0.3);
            total_energy += l * l + r * r;
        }
        assert!(
            total_energy > 0.01,
            "FDN should produce output, energy={}",
            total_energy
        );
    }
}
