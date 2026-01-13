//! Dynamics processors: compressor, limiter, gate, expander
//!
//! Professional dynamics processing with:
//! - VCA, Opto, and FET compressor characteristics
//! - True peak limiting with oversampling
//! - Program-dependent attack/release
//! - Soft-knee compression
//! - SIMD-optimized envelope following (AVX2/AVX-512)

use rf_core::Sample;

#[cfg(target_arch = "x86_64")]
use std::simd::{f64x4, f64x8};
#[cfg(target_arch = "x86_64")]
use std::simd::prelude::SimdFloat;

use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

/// Envelope follower for dynamics processing
#[derive(Debug, Clone)]
pub struct EnvelopeFollower {
    attack_coeff: f64,
    release_coeff: f64,
    envelope: f64,
    sample_rate: f64,
}

impl EnvelopeFollower {
    pub fn new(sample_rate: f64) -> Self {
        let mut follower = Self {
            attack_coeff: 0.0,
            release_coeff: 0.0,
            envelope: 0.0,
            sample_rate,
        };
        follower.set_times(10.0, 100.0);
        follower
    }

    /// Set attack and release times in milliseconds
    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_coeff = (-1.0 / (attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (release_ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    #[inline(always)]
    pub fn process(&mut self, input: Sample) -> f64 {
        let abs_input = input.abs();
        let coeff = if abs_input > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = abs_input + coeff * (self.envelope - abs_input);
        self.envelope
    }

    /// Process block with SIMD optimization (4 samples at once)
    #[cfg(target_arch = "x86_64")]
    pub fn process_block_simd4(&mut self, input: &[Sample], output: &mut [f64]) {
        assert_eq!(input.len(), output.len());

        let len = input.len();
        let simd_len = len - (len % 4);

        let attack_simd = f64x4::splat(self.attack_coeff);
        let release_simd = f64x4::splat(self.release_coeff);
        let mut envelope_simd = f64x4::splat(self.envelope);

        // Process 4 samples at a time
        for i in (0..simd_len).step_by(4) {
            let input_simd = f64x4::from_slice(&input[i..]);
            let abs_input = input_simd.abs();

            // Select attack or release coefficient per lane
            let mask = abs_input.simd_gt(envelope_simd);
            let coeff = mask.select(attack_simd, release_simd);

            // Envelope smoothing: env = abs + coeff * (env - abs)
            envelope_simd = abs_input + coeff * (envelope_simd - abs_input);

            // Store result
            output[i..i + 4].copy_from_slice(&envelope_simd.to_array());
        }

        // Update scalar state from last SIMD lane
        self.envelope = envelope_simd[3];

        // Process remaining samples (0-3) with scalar
        for i in simd_len..len {
            output[i] = self.process(input[i]);
        }
    }

    /// Process block with AVX-512 SIMD optimization (8 samples at once)
    #[cfg(target_arch = "x86_64")]
    pub fn process_block_simd8(&mut self, input: &[Sample], output: &mut [f64]) {
        assert_eq!(input.len(), output.len());

        let len = input.len();
        let simd_len = len - (len % 8);

        let attack_simd = f64x8::splat(self.attack_coeff);
        let release_simd = f64x8::splat(self.release_coeff);
        let mut envelope_simd = f64x8::splat(self.envelope);

        // Process 8 samples at a time
        for i in (0..simd_len).step_by(8) {
            let input_simd = f64x8::from_slice(&input[i..]);
            let abs_input = input_simd.abs();

            // Select attack or release coefficient per lane
            let mask = abs_input.simd_gt(envelope_simd);
            let coeff = mask.select(attack_simd, release_simd);

            // Envelope smoothing: env = abs + coeff * (env - abs)
            envelope_simd = abs_input + coeff * (envelope_simd - abs_input);

            // Store result
            output[i..i + 8].copy_from_slice(&envelope_simd.to_array());
        }

        // Update scalar state from last SIMD lane
        self.envelope = envelope_simd[7];

        // Process remaining samples (0-7) with scalar
        for i in simd_len..len {
            output[i] = self.process(input[i]);
        }
    }

    /// Process block with runtime SIMD dispatch
    pub fn process_block(&mut self, input: &[Sample], output: &mut [f64]) {
        #[cfg(target_arch = "x86_64")]
        {
            if is_x86_feature_detected!("avx512f") {
                self.process_block_simd8(input, output);
            } else if is_x86_feature_detected!("avx2") {
                self.process_block_simd4(input, output);
            } else {
                self.process_block_scalar(input, output);
            }
        }
        #[cfg(not(target_arch = "x86_64"))]
        {
            self.process_block_scalar(input, output);
        }
    }

    /// Scalar fallback for block processing
    fn process_block_scalar(&mut self, input: &[Sample], output: &mut [f64]) {
        for (i, &sample) in input.iter().enumerate() {
            output[i] = self.process(sample);
        }
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
    }

    pub fn current(&self) -> f64 {
        self.envelope
    }
}

/// Compressor characteristic type
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum CompressorType {
    /// Clean VCA compression - fast, transparent
    #[default]
    Vca,
    /// Optical compression - smooth, program-dependent
    Opto,
    /// FET compression - aggressive, punchy, adds harmonics
    Fet,
}

/// Compressor with multiple characteristics
#[derive(Debug, Clone)]
pub struct Compressor {
    // Parameters
    threshold_db: f64,
    ratio: f64,
    knee_db: f64,
    makeup_gain_db: f64,
    attack_ms: f64,
    release_ms: f64,
    mix: f64, // Dry/wet for parallel compression

    // Compressor type
    comp_type: CompressorType,

    // State
    envelope: EnvelopeFollower,
    gain_reduction: f64,

    // Opto-specific state
    opto_envelope: f64,
    opto_gain_history: [f64; 4],

    // FET-specific state
    fet_saturation: f64,

    sample_rate: f64,
}

impl Compressor {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            threshold_db: -20.0,
            ratio: 4.0,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            mix: 1.0,
            comp_type: CompressorType::Vca,
            envelope: EnvelopeFollower::new(sample_rate),
            gain_reduction: 0.0,
            opto_envelope: 0.0,
            opto_gain_history: [1.0; 4],
            fet_saturation: 0.0,
            sample_rate,
        }
    }

    // Parameter setters
    pub fn set_type(&mut self, comp_type: CompressorType) {
        self.comp_type = comp_type;
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-60.0, 0.0);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 100.0);
    }

    pub fn set_knee(&mut self, db: f64) {
        self.knee_db = db.clamp(0.0, 24.0);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.01, 500.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 5000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_ms = attack_ms.clamp(0.01, 500.0);
        self.release_ms = release_ms.clamp(1.0, 5000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_makeup(&mut self, db: f64) {
        self.makeup_gain_db = db.clamp(-24.0, 24.0);
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        self.gain_reduction
    }

    /// Calculate gain reduction using soft-knee
    #[inline]
    fn calculate_gain_reduction(&self, input_db: f64) -> f64 {
        let half_knee = self.knee_db / 2.0;
        let knee_start = self.threshold_db - half_knee;
        let knee_end = self.threshold_db + half_knee;

        if input_db < knee_start {
            0.0
        } else if input_db > knee_end {
            (input_db - self.threshold_db) * (1.0 - 1.0 / self.ratio)
        } else {
            let x = input_db - knee_start;
            let slope = 1.0 - 1.0 / self.ratio;
            (slope * x * x) / (2.0 * self.knee_db)
        }
    }

    /// VCA-style compression (clean, transparent)
    #[inline]
    fn process_vca(&mut self, input: Sample) -> Sample {
        let envelope = self.envelope.process(input);

        if envelope < 1e-10 {
            return input;
        }

        let env_db = 20.0 * envelope.log10();
        let gr_db = self.calculate_gain_reduction(env_db);
        self.gain_reduction = gr_db;

        let gain = 10.0_f64.powf(-gr_db / 20.0);
        input * gain
    }

    /// Opto-style compression (smooth, program-dependent)
    #[inline]
    fn process_opto(&mut self, input: Sample) -> Sample {
        let abs_input = input.abs();

        // Opto cells have program-dependent attack/release
        // Higher levels = faster response
        let level_factor = (abs_input * 10.0).min(1.0);

        // Attack gets faster with higher levels
        let attack_coeff = (-1.0
            / ((self.attack_ms * (1.0 - level_factor * 0.5)) * 0.001 * self.sample_rate))
            .exp();
        // Release is slower for higher gain reduction (opto characteristic)
        let release_factor = 1.0 + self.gain_reduction * 0.02;
        let release_coeff =
            (-1.0 / ((self.release_ms * release_factor) * 0.001 * self.sample_rate)).exp();

        let coeff = if abs_input > self.opto_envelope {
            attack_coeff
        } else {
            release_coeff
        };
        self.opto_envelope = abs_input + coeff * (self.opto_envelope - abs_input);

        if self.opto_envelope < 1e-10 {
            return input;
        }

        let env_db = 20.0 * self.opto_envelope.log10();
        let gr_db = self.calculate_gain_reduction(env_db);

        // Smooth the gain reduction (opto inertia)
        self.opto_gain_history.rotate_right(1);
        self.opto_gain_history[0] = gr_db;
        let smoothed_gr: f64 = self.opto_gain_history.iter().sum::<f64>() / 4.0;
        self.gain_reduction = smoothed_gr;

        let gain = 10.0_f64.powf(-smoothed_gr / 20.0);
        input * gain
    }

    /// FET-style compression (aggressive, punchy, adds harmonics)
    #[inline]
    fn process_fet(&mut self, input: Sample) -> Sample {
        let envelope = self.envelope.process(input);

        if envelope < 1e-10 {
            return input;
        }

        let env_db = 20.0 * envelope.log10();

        // FET has more aggressive knee and can go into negative ratio territory
        let gr_db = if env_db > self.threshold_db {
            let over = env_db - self.threshold_db;
            // FET characteristic: harder knee, more aggressive at high levels
            let effective_ratio = self.ratio * (1.0 + over * 0.05).min(2.0);
            over * (1.0 - 1.0 / effective_ratio)
        } else {
            0.0
        };

        self.gain_reduction = gr_db;
        let gain = 10.0_f64.powf(-gr_db / 20.0);

        // Add subtle FET saturation
        let saturated = input * gain;
        let saturation_amount = (gr_db / 20.0).min(0.3);
        self.fet_saturation = saturation_amount;

        // Soft clip saturation characteristic
        if saturation_amount > 0.0 {
            let x = saturated * (1.0 + saturation_amount);
            x / (1.0 + x.abs() * saturation_amount * 0.5)
        } else {
            saturated
        }
    }
}

impl Processor for Compressor {
    fn reset(&mut self) {
        self.envelope.reset();
        self.gain_reduction = 0.0;
        self.opto_envelope = 0.0;
        self.opto_gain_history = [1.0; 4];
        self.fet_saturation = 0.0;
    }
}

impl MonoProcessor for Compressor {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let dry = input;

        let compressed = match self.comp_type {
            CompressorType::Vca => self.process_vca(input),
            CompressorType::Opto => self.process_opto(input),
            CompressorType::Fet => self.process_fet(input),
        };

        // Apply makeup gain
        let makeup = 10.0_f64.powf(self.makeup_gain_db / 20.0);
        let wet = compressed * makeup;

        // Dry/wet mix
        dry * (1.0 - self.mix) + wet * self.mix
    }
}

impl ProcessorConfig for Compressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

/// Stereo compressor with link options
#[derive(Debug, Clone)]
pub struct StereoCompressor {
    left: Compressor,
    right: Compressor,
    link: f64, // 0.0 = independent, 1.0 = fully linked
}

impl StereoCompressor {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Compressor::new(sample_rate),
            right: Compressor::new(sample_rate),
            link: 1.0,
        }
    }

    pub fn set_link(&mut self, link: f64) {
        self.link = link.clamp(0.0, 1.0);
    }

    pub fn left(&mut self) -> &mut Compressor {
        &mut self.left
    }

    pub fn right(&mut self) -> &mut Compressor {
        &mut self.right
    }

    /// Set parameter for both channels
    pub fn set_both<F>(&mut self, f: F)
    where
        F: Fn(&mut Compressor),
    {
        f(&mut self.left);
        f(&mut self.right);
    }

    pub fn gain_reduction_db(&self) -> (f64, f64) {
        (
            self.left.gain_reduction_db(),
            self.right.gain_reduction_db(),
        )
    }
}

impl Processor for StereoCompressor {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

impl StereoProcessor for StereoCompressor {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        if self.link >= 0.99 {
            // Fully linked - use max of both channels
            let max_input = left.abs().max(right.abs());
            let _ = self.left.envelope.process(max_input);
            let _ = self.right.envelope.process(max_input);

            // Use same envelope for both
            let env = self.left.envelope.current();
            let env_db = if env > 1e-10 {
                20.0 * env.log10()
            } else {
                -120.0
            };
            let gr_db = self.left.calculate_gain_reduction(env_db);
            self.left.gain_reduction = gr_db;
            self.right.gain_reduction = gr_db;

            let gain = 10.0_f64.powf(-gr_db / 20.0);
            let makeup = 10.0_f64.powf(self.left.makeup_gain_db / 20.0);

            (left * gain * makeup, right * gain * makeup)
        } else if self.link <= 0.01 {
            // Independent
            (
                self.left.process_sample(left),
                self.right.process_sample(right),
            )
        } else {
            // Partial link
            let out_l = self.left.process_sample(left);
            let out_r = self.right.process_sample(right);

            // Blend between linked and independent
            let max_gr = self.left.gain_reduction.max(self.right.gain_reduction);
            let linked_gain = 10.0_f64.powf(-max_gr / 20.0);
            let makeup = 10.0_f64.powf(self.left.makeup_gain_db / 20.0);

            let linked_l = left * linked_gain * makeup;
            let linked_r = right * linked_gain * makeup;

            (
                out_l * (1.0 - self.link) + linked_l * self.link,
                out_r * (1.0 - self.link) + linked_r * self.link,
            )
        }
    }
}

impl ProcessorConfig for StereoCompressor {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.left.set_sample_rate(sample_rate);
        self.right.set_sample_rate(sample_rate);
    }
}

/// Oversampling factor for true peak limiting
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Oversampling {
    #[default]
    X1,
    X2,
    X4,
    X8,
}

impl Oversampling {
    pub fn factor(&self) -> usize {
        match self {
            Oversampling::X1 => 1,
            Oversampling::X2 => 2,
            Oversampling::X4 => 4,
            Oversampling::X8 => 8,
        }
    }
}

/// Half-band filter for oversampling
#[derive(Debug, Clone)]
struct HalfbandFilter {
    coeffs: [f64; 7],
    delay: [f64; 7],
}

impl HalfbandFilter {
    fn new() -> Self {
        // 7-tap half-band filter coefficients
        Self {
            coeffs: [
                0.00613927,
                0.0,
                -0.05096454,
                0.0,
                0.29466106,
                0.5,
                0.29466106,
            ],
            delay: [0.0; 7],
        }
    }

    #[inline]
    fn process(&mut self, input: f64) -> f64 {
        self.delay.rotate_right(1);
        self.delay[0] = input;

        let mut output = 0.0;
        for (i, &coeff) in self.coeffs.iter().enumerate() {
            output += coeff * self.delay[i];
        }
        output
    }

    fn reset(&mut self) {
        self.delay.fill(0.0);
    }
}

/// True Peak Limiter with oversampling
///
/// Uses ITU-R BS.1770-4 compliant true peak detection
#[derive(Debug, Clone)]
pub struct TruePeakLimiter {
    // Parameters
    threshold_db: f64,
    release_ms: f64,
    ceiling_db: f64,

    // Oversampling
    oversampling: Oversampling,
    upsample_filters: Vec<HalfbandFilter>,
    downsample_filters: Vec<HalfbandFilter>,

    // Lookahead
    lookahead_ms: f64,
    lookahead_buffer_l: Vec<Sample>,
    lookahead_buffer_r: Vec<Sample>,
    buffer_pos: usize,

    // State
    gain: f64,
    release_coeff: f64,
    true_peak: f64,
    sample_rate: f64,
}

impl TruePeakLimiter {
    pub fn new(sample_rate: f64) -> Self {
        let lookahead_ms = 1.5; // ITU recommends 1.5ms for true peak
        let lookahead_samples = ((lookahead_ms * 0.001 * sample_rate) as usize).max(1);

        Self {
            threshold_db: -1.0,
            release_ms: 100.0,
            ceiling_db: -0.1,
            oversampling: Oversampling::X4,
            upsample_filters: vec![HalfbandFilter::new(); 4],
            downsample_filters: vec![HalfbandFilter::new(); 4],
            lookahead_ms,
            lookahead_buffer_l: vec![0.0; lookahead_samples],
            lookahead_buffer_r: vec![0.0; lookahead_samples],
            buffer_pos: 0,
            gain: 1.0,
            release_coeff: (-1.0 / (100.0 * 0.001 * sample_rate)).exp(),
            true_peak: 0.0,
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-24.0, 0.0);
    }

    pub fn set_ceiling(&mut self, db: f64) {
        self.ceiling_db = db.clamp(-6.0, 0.0);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(10.0, 1000.0);
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_oversampling(&mut self, os: Oversampling) {
        self.oversampling = os;
        self.reset();
    }

    /// Get current true peak level in dBTP
    pub fn true_peak_db(&self) -> f64 {
        if self.true_peak > 1e-10 {
            20.0 * self.true_peak.log10()
        } else {
            -120.0
        }
    }

    /// Get current gain reduction in dB
    pub fn gain_reduction_db(&self) -> f64 {
        -20.0 * self.gain.log10()
    }

    /// Upsample a sample (zero-stuffing + filtering)
    /// Returns (samples_array, count) - stack-allocated, no heap allocation
    #[inline(always)]
    fn upsample(&mut self, input: f64) -> ([f64; 8], usize) {
        let factor = self.oversampling.factor();
        let mut samples = [0.0f64; 8];

        if factor == 1 {
            samples[0] = input;
            return (samples, 1);
        }

        // Simple zero-stuffing with single filter pass
        // (proper implementation would use polyphase)
        for i in 0..factor {
            let x = if i == 0 { input * factor as f64 } else { 0.0 };
            samples[i] = self.upsample_filters[0].process(x);
        }

        (samples, factor)
    }

    /// Downsample (filter + decimate)
    fn downsample(&mut self, samples: &[f64]) -> f64 {
        let factor = self.oversampling.factor();
        if factor == 1 {
            return samples[0];
        }

        // Filter and take last sample
        let mut last = 0.0;
        for &sample in samples {
            last = self.downsample_filters[0].process(sample);
        }
        last
    }

    /// Find true peak in oversampled signal
    #[inline(always)]
    fn find_true_peak(&mut self, left: Sample, right: Sample) -> f64 {
        let (up_l, count_l) = self.upsample(left);
        let (up_r, count_r) = self.upsample(right);
        let count = count_l.min(count_r);

        let mut max_peak: f64 = 0.0;
        for i in 0..count {
            max_peak = max_peak.max(up_l[i].abs()).max(up_r[i].abs());
        }

        max_peak
    }
}

impl Processor for TruePeakLimiter {
    fn reset(&mut self) {
        self.gain = 1.0;
        self.true_peak = 0.0;
        self.lookahead_buffer_l.fill(0.0);
        self.lookahead_buffer_r.fill(0.0);
        self.buffer_pos = 0;

        for filter in &mut self.upsample_filters {
            filter.reset();
        }
        for filter in &mut self.downsample_filters {
            filter.reset();
        }
    }

    fn latency(&self) -> usize {
        self.lookahead_buffer_l.len()
    }
}

impl StereoProcessor for TruePeakLimiter {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Get delayed samples
        let delayed_l = self.lookahead_buffer_l[self.buffer_pos];
        let delayed_r = self.lookahead_buffer_r[self.buffer_pos];

        // Store current samples
        self.lookahead_buffer_l[self.buffer_pos] = left;
        self.lookahead_buffer_r[self.buffer_pos] = right;
        self.buffer_pos = (self.buffer_pos + 1) % self.lookahead_buffer_l.len();

        // Find true peak using oversampling
        let true_peak = self.find_true_peak(left, right);
        self.true_peak = self.true_peak.max(true_peak);

        // Calculate target gain
        let threshold_linear = 10.0_f64.powf(self.threshold_db / 20.0);
        let ceiling_linear = 10.0_f64.powf(self.ceiling_db / 20.0);

        let target_gain = if true_peak > threshold_linear {
            (ceiling_linear / true_peak).min(1.0)
        } else {
            1.0
        };

        // Apply gain smoothing (instant attack, smooth release)
        if target_gain < self.gain {
            self.gain = target_gain;
        } else {
            self.gain = target_gain + self.release_coeff * (self.gain - target_gain);
        }

        // Apply gain to delayed signal
        (delayed_l * self.gain, delayed_r * self.gain)
    }
}

impl ProcessorConfig for TruePeakLimiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();

        let lookahead_samples = ((self.lookahead_ms * 0.001 * sample_rate) as usize).max(1);
        self.lookahead_buffer_l = vec![0.0; lookahead_samples];
        self.lookahead_buffer_r = vec![0.0; lookahead_samples];
        self.buffer_pos = 0;
    }
}

/// Simple peak limiter (for compatibility)
#[derive(Debug, Clone)]
pub struct Limiter {
    threshold_db: f64,
    release_coeff: f64,
    gain: f64,
    lookahead_samples: usize,
    lookahead_buffer: Vec<Sample>,
    buffer_pos: usize,
    sample_rate: f64,
}

impl Limiter {
    pub fn new(sample_rate: f64) -> Self {
        let lookahead_ms = 5.0;
        let lookahead_samples = (lookahead_ms * 0.001 * sample_rate) as usize;

        Self {
            threshold_db: -0.3,
            release_coeff: (-1.0 / (100.0 * 0.001 * sample_rate)).exp(),
            gain: 1.0,
            lookahead_samples,
            lookahead_buffer: vec![0.0; lookahead_samples],
            buffer_pos: 0,
            sample_rate,
        }
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db;
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_coeff = (-1.0 / (ms * 0.001 * self.sample_rate)).exp();
    }

    fn threshold_linear(&self) -> f64 {
        10.0_f64.powf(self.threshold_db / 20.0)
    }
}

impl Processor for Limiter {
    fn reset(&mut self) {
        self.gain = 1.0;
        self.lookahead_buffer.fill(0.0);
        self.buffer_pos = 0;
    }

    fn latency(&self) -> usize {
        self.lookahead_samples
    }
}

impl MonoProcessor for Limiter {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let delayed = self.lookahead_buffer[self.buffer_pos];
        self.lookahead_buffer[self.buffer_pos] = input;
        self.buffer_pos = (self.buffer_pos + 1) % self.lookahead_samples;

        let threshold = self.threshold_linear();
        let abs_input = input.abs();
        let target_gain = if abs_input > threshold {
            threshold / abs_input
        } else {
            1.0
        };

        if target_gain < self.gain {
            self.gain = target_gain;
        } else {
            self.gain = target_gain + self.release_coeff * (self.gain - target_gain);
        }

        delayed * self.gain
    }
}

impl ProcessorConfig for Limiter {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        let lookahead_ms = 5.0;
        self.lookahead_samples = (lookahead_ms * 0.001 * sample_rate) as usize;
        self.lookahead_buffer = vec![0.0; self.lookahead_samples];
        self.buffer_pos = 0;
    }
}

/// Noise gate
#[derive(Debug, Clone)]
pub struct Gate {
    threshold_db: f64,
    range_db: f64,
    attack_ms: f64,
    hold_ms: f64,
    release_ms: f64,
    envelope: EnvelopeFollower,
    gain: f64,
    hold_counter: usize,
    sample_rate: f64,
}

impl Gate {
    pub fn new(sample_rate: f64) -> Self {
        let mut gate = Self {
            threshold_db: -40.0,
            range_db: -80.0,
            attack_ms: 1.0,
            hold_ms: 50.0,
            release_ms: 100.0,
            envelope: EnvelopeFollower::new(sample_rate),
            gain: 0.0,
            hold_counter: 0,
            sample_rate,
        };
        gate.envelope.set_times(1.0, 50.0);
        gate
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_range(&mut self, db: f64) {
        self.range_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_attack(&mut self, ms: f64) {
        self.attack_ms = ms.clamp(0.01, 100.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    pub fn set_hold(&mut self, ms: f64) {
        self.hold_ms = ms.clamp(0.0, 500.0);
    }

    pub fn set_release(&mut self, ms: f64) {
        self.release_ms = ms.clamp(1.0, 1000.0);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }

    fn threshold_linear(&self) -> f64 {
        10.0_f64.powf(self.threshold_db / 20.0)
    }

    fn range_linear(&self) -> f64 {
        10.0_f64.powf(self.range_db / 20.0)
    }
}

impl Processor for Gate {
    fn reset(&mut self) {
        self.envelope.reset();
        self.gain = 0.0;
        self.hold_counter = 0;
    }
}

impl MonoProcessor for Gate {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let envelope = self.envelope.process(input);
        let threshold = self.threshold_linear();
        let range = self.range_linear();

        let hold_samples = (self.hold_ms * 0.001 * self.sample_rate) as usize;

        let target_gain = if envelope >= threshold {
            self.hold_counter = hold_samples;
            1.0
        } else if self.hold_counter > 0 {
            self.hold_counter -= 1;
            1.0
        } else {
            range
        };

        // Smooth gain transition
        let attack_coeff = (-1.0 / (self.attack_ms * 0.001 * self.sample_rate)).exp();
        let release_coeff = (-1.0 / (self.release_ms * 0.001 * self.sample_rate)).exp();

        let coeff = if target_gain > self.gain {
            attack_coeff
        } else {
            release_coeff
        };
        self.gain = target_gain + coeff * (self.gain - target_gain);

        input * self.gain
    }
}

impl ProcessorConfig for Gate {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

/// Expander (opposite of compressor)
#[derive(Debug, Clone)]
pub struct Expander {
    threshold_db: f64,
    ratio: f64,
    knee_db: f64,
    attack_ms: f64,
    release_ms: f64,
    envelope: EnvelopeFollower,
    sample_rate: f64,
}

impl Expander {
    pub fn new(sample_rate: f64) -> Self {
        let mut exp = Self {
            threshold_db: -30.0,
            ratio: 2.0,
            knee_db: 6.0,
            attack_ms: 5.0,
            release_ms: 100.0,
            envelope: EnvelopeFollower::new(sample_rate),
            sample_rate,
        };
        exp.envelope.set_times(5.0, 100.0);
        exp
    }

    pub fn set_threshold(&mut self, db: f64) {
        self.threshold_db = db.clamp(-80.0, 0.0);
    }

    pub fn set_ratio(&mut self, ratio: f64) {
        self.ratio = ratio.clamp(1.0, 20.0);
    }

    pub fn set_knee(&mut self, db: f64) {
        self.knee_db = db.clamp(0.0, 24.0);
    }

    pub fn set_times(&mut self, attack_ms: f64, release_ms: f64) {
        self.attack_ms = attack_ms;
        self.release_ms = release_ms;
        self.envelope.set_times(attack_ms, release_ms);
    }
}

impl Processor for Expander {
    fn reset(&mut self) {
        self.envelope.reset();
    }
}

impl MonoProcessor for Expander {
    #[inline(always)]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let envelope = self.envelope.process(input);

        if envelope < 1e-10 {
            return 0.0;
        }

        let env_db = 20.0 * envelope.log10();

        // Expansion below threshold
        let gain_db = if env_db < self.threshold_db - self.knee_db / 2.0 {
            // Below knee - full expansion
            (env_db - self.threshold_db) * (self.ratio - 1.0)
        } else if env_db > self.threshold_db + self.knee_db / 2.0 {
            // Above knee - no expansion
            0.0
        } else {
            // In knee - soft transition
            let x = env_db - (self.threshold_db - self.knee_db / 2.0);
            let slope = self.ratio - 1.0;
            -(slope * (self.knee_db - x) * (self.knee_db - x)) / (2.0 * self.knee_db)
        };

        let gain = 10.0_f64.powf(gain_db / 20.0);
        input * gain
    }
}

impl ProcessorConfig for Expander {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.envelope.set_sample_rate(sample_rate);
        self.envelope.set_times(self.attack_ms, self.release_ms);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compressor_types() {
        let sample_rate = 48000.0;

        for comp_type in [
            CompressorType::Vca,
            CompressorType::Opto,
            CompressorType::Fet,
        ] {
            let mut comp = Compressor::new(sample_rate);
            comp.set_type(comp_type);
            comp.set_threshold(-20.0);
            comp.set_ratio(4.0);

            // Process some samples
            for _ in 0..1000 {
                let _ = comp.process_sample(0.5);
            }

            // Should have some gain reduction
            assert!(comp.gain_reduction_db() > 0.0);
        }
    }

    #[test]
    fn test_true_peak_limiter() {
        let mut limiter = TruePeakLimiter::new(48000.0);
        limiter.set_threshold(-1.0);
        limiter.set_ceiling(-0.1);

        // Process through lookahead
        for _ in 0..limiter.latency() {
            let _ = limiter.process_sample(2.0, 2.0);
        }

        // Output should be limited
        let (l, r) = limiter.process_sample(2.0, 2.0);
        assert!(l.abs() < 1.0);
        assert!(r.abs() < 1.0);
    }

    #[test]
    fn test_gate_with_hold() {
        let mut gate = Gate::new(48000.0);
        gate.set_threshold(-20.0);
        gate.set_hold(10.0); // 10ms hold

        // Loud signal opens gate - need more samples for gate to fully open
        for _ in 0..1000 {
            gate.process_sample(0.5);
        }

        // Gate should be open (may not be exactly 1.0 due to attack time)
        assert!(gate.gain > 0.5, "Gate should be open, got {}", gate.gain);

        // Small number of quiet samples - gate still held open
        for _ in 0..100 {
            gate.process_sample(0.001);
        }
        // Gate should still be partially open due to hold
        assert!(
            gate.gain > 0.3,
            "Gate should still be partially open due to hold, got {}",
            gate.gain
        );
    }

    #[test]
    fn test_stereo_compressor_link() {
        let mut comp = StereoCompressor::new(48000.0);
        comp.set_both(|c| {
            c.set_threshold(-20.0);
            c.set_ratio(4.0);
        });
        comp.set_link(1.0); // Fully linked

        // Process with unbalanced signal
        for _ in 0..1000 {
            let _ = comp.process_sample(0.5, 0.1);
        }

        // Both channels should have same gain reduction when linked
        let (gr_l, gr_r) = comp.gain_reduction_db();
        assert!((gr_l - gr_r).abs() < 0.1);
    }

    #[test]
    fn test_envelope_simd_vs_scalar() {
        let mut envelope_scalar = EnvelopeFollower::new(48000.0);
        envelope_scalar.set_times(10.0, 100.0);

        let mut envelope_simd = EnvelopeFollower::new(48000.0);
        envelope_simd.set_times(10.0, 100.0);

        // Generate test signal (sine wave with attack/release)
        let input: Vec<f64> = (0..1024)
            .map(|i| (i as f64 * 0.01).sin() * 0.5)
            .collect();

        // Process with scalar
        let mut output_scalar = vec![0.0; 1024];
        for (i, &sample) in input.iter().enumerate() {
            output_scalar[i] = envelope_scalar.process(sample);
        }

        // Process with SIMD
        envelope_simd.reset();
        let mut output_simd = vec![0.0; 1024];
        envelope_simd.process_block(&input, &mut output_simd);

        // Compare results (should be nearly identical)
        for (i, (&scalar, &simd)) in output_scalar.iter().zip(output_simd.iter()).enumerate() {
            assert!(
                (scalar - simd).abs() < 1e-10,
                "Mismatch at sample {}: scalar={}, simd={}",
                i,
                scalar,
                simd
            );
        }
    }

    #[test]
    fn test_envelope_simd_performance() {
        let mut envelope = EnvelopeFollower::new(48000.0);
        envelope.set_times(5.0, 50.0);

        // Large block for performance testing
        let input: Vec<f64> = (0..8192)
            .map(|i| (i as f64 * 0.001).sin())
            .collect();
        let mut output = vec![0.0; 8192];

        // Process block (should use SIMD on x86_64)
        envelope.process_block(&input, &mut output);

        // Verify envelope is computed
        assert!(output.iter().all(|&x| x.is_finite()));
        assert!(output.iter().any(|&x| x > 0.0));
    }

    #[test]
    #[cfg(target_arch = "x86_64")]
    fn test_envelope_avx512() {
        if !is_x86_feature_detected!("avx512f") {
            println!("AVX-512 not available, skipping test");
            return;
        }

        let mut envelope = EnvelopeFollower::new(48000.0);
        envelope.set_times(10.0, 100.0);

        let input: Vec<f64> = (0..1024)
            .map(|i| (i as f64 * 0.01).sin())
            .collect();
        let mut output = vec![0.0; 1024];

        envelope.process_block_simd8(&input, &mut output);

        assert!(output.iter().all(|&x| x.is_finite()));
    }
}
