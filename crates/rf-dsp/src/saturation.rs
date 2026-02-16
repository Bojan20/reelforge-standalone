//! Saturation and distortion processors
//!
//! Includes:
//! - Tape saturation (with hysteresis)
//! - Tube saturation
//! - Transistor saturation
//! - Soft/hard clipping
//! - Waveshaping
//!
//! Anti-aliasing:
//! - Oversampled processing via `OversampledSaturator`
//! - 2x/4x/8x/16x modes for alias-free nonlinear processing

use rf_core::Sample;
use std::f64::consts::PI;

use crate::oversampling::{GlobalOversampler, OversampleFactor, OversampleQuality};
use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

/// Saturation type
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum SaturationType {
    /// Tape: warm, compressed, slight high-frequency rolloff
    #[default]
    Tape,
    /// Tube: even harmonics, warm
    Tube,
    /// Transistor: odd harmonics, edgier
    Transistor,
    /// Soft clip: smooth limiting
    SoftClip,
    /// Hard clip: digital-style clipping
    HardClip,
    /// Foldback: creative distortion
    Foldback,
}

/// Saturation processor with multiple types
#[derive(Debug, Clone)]
pub struct Saturator {
    sat_type: SaturationType,
    drive: f64,  // Input gain (1.0 = unity)
    mix: f64,    // Dry/wet (0.0 = dry, 1.0 = wet)
    output: f64, // Output gain

    // Tape-specific state
    tape_bias: f64,
    tape_prev: f64,

    // Tube-specific state
    tube_bias: f64,

    sample_rate: f64,
}

impl Saturator {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sat_type: SaturationType::Tape,
            drive: 1.0,
            mix: 1.0,
            output: 1.0,
            tape_bias: 0.0,
            tape_prev: 0.0,
            tube_bias: 0.0,
            sample_rate,
        }
    }

    pub fn set_type(&mut self, sat_type: SaturationType) {
        self.sat_type = sat_type;
    }

    /// Set drive amount (1.0 = unity, higher = more saturation)
    pub fn set_drive(&mut self, drive: f64) {
        self.drive = drive.clamp(0.1, 100.0);
    }

    /// Set drive in dB
    pub fn set_drive_db(&mut self, db: f64) {
        self.drive = 10.0_f64.powf(db.clamp(-20.0, 40.0) / 20.0);
    }

    /// Set dry/wet mix
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Set output level in dB
    pub fn set_output_db(&mut self, db: f64) {
        self.output = 10.0_f64.powf(db.clamp(-24.0, 12.0) / 20.0);
    }

    /// Set tape bias (affects hysteresis)
    pub fn set_tape_bias(&mut self, bias: f64) {
        self.tape_bias = bias.clamp(0.0, 1.0);
    }

    /// Tape saturation with simplified hysteresis
    #[inline]
    fn process_tape(&mut self, input: Sample) -> Sample {
        let driven = input * self.drive;

        // Simplified tape hysteresis model
        // Based on Jiles-Atherton model approximation
        let delta = driven - self.tape_prev;
        let hysteresis = delta * self.tape_bias * 0.1;

        // Soft saturation curve (tanh-like but asymmetric for even harmonics)
        let x = driven + hysteresis;
        let saturated = x / (1.0 + x.abs() * 0.5).powf(0.8);

        // High frequency rolloff (tape head characteristics)
        // Simple one-pole lowpass
        let filtered = saturated * 0.9 + self.tape_prev * 0.1;
        self.tape_prev = filtered;

        filtered
    }

    /// Tube saturation (triode model)
    #[inline]
    fn process_tube(&mut self, input: Sample) -> Sample {
        let driven = input * self.drive;

        // Asymmetric soft clipping (tube characteristic)
        // Positive and negative half-waves saturate differently
        let saturated = if driven >= 0.0 {
            // Positive: softer saturation
            driven / (1.0 + driven.abs() * 0.3)
        } else {
            // Negative: slightly harder clip (grid conduction)
            let x = driven * 1.2;
            x / (1.0 + x.abs() * 0.5)
        };

        // Add subtle even harmonics (2nd harmonic mainly)

        saturated + saturated.powi(2) * 0.1 * self.drive.min(2.0)
    }

    /// Transistor saturation
    #[inline]
    fn process_transistor(&mut self, input: Sample) -> Sample {
        let driven = input * self.drive;

        // Symmetric hard clipping (odd harmonics)
        let x = driven;
        let saturated = (3.0 * x) / (1.0 + 2.0 * x.abs() + x * x);

        // Crossover distortion simulation (subtle)

        if x.abs() < 0.1 {
            x * 0.8 + x.powi(3) * 2.0
        } else {
            saturated
        }
    }

    /// Soft clip (smooth limiter)
    #[inline]
    fn process_soft_clip(&self, input: Sample) -> Sample {
        let driven = input * self.drive;

        // Polynomial soft clip
        if driven.abs() <= 1.0 {
            driven - driven.powi(3) / 3.0
        } else {
            driven.signum() * 2.0 / 3.0
        }
    }

    /// Hard clip
    #[inline]
    fn process_hard_clip(&self, input: Sample) -> Sample {
        let driven = input * self.drive;
        driven.clamp(-1.0, 1.0)
    }

    /// Foldback distortion
    #[inline]
    fn process_foldback(&self, input: Sample) -> Sample {
        let driven = input * self.drive;

        // Fold signal back when it exceeds threshold
        let threshold = 1.0;
        let mut x = driven;

        // Multiple fold iterations for extreme settings
        for _ in 0..4 {
            if x > threshold {
                x = threshold - (x - threshold);
            } else if x < -threshold {
                x = -threshold - (x + threshold);
            }
        }

        x
    }
}

impl Processor for Saturator {
    fn reset(&mut self) {
        self.tape_prev = 0.0;
        self.tube_bias = 0.0;
    }
}

impl MonoProcessor for Saturator {
    #[inline]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let saturated = match self.sat_type {
            SaturationType::Tape => self.process_tape(input),
            SaturationType::Tube => self.process_tube(input),
            SaturationType::Transistor => self.process_transistor(input),
            SaturationType::SoftClip => self.process_soft_clip(input),
            SaturationType::HardClip => self.process_hard_clip(input),
            SaturationType::Foldback => self.process_foldback(input),
        };

        // Dry/wet mix and output gain
        let mixed = input * (1.0 - self.mix) + saturated * self.mix;
        mixed * self.output
    }
}

impl ProcessorConfig for Saturator {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }
}

/// Stereo saturator with independent or linked processing
#[derive(Debug, Clone)]
pub struct StereoSaturator {
    left: Saturator,
    right: Saturator,
    link: bool,
}

impl StereoSaturator {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            left: Saturator::new(sample_rate),
            right: Saturator::new(sample_rate),
            link: true,
        }
    }

    pub fn set_link(&mut self, link: bool) {
        self.link = link;
    }

    /// Apply settings to both channels
    pub fn set_both<F>(&mut self, f: F)
    where
        F: Fn(&mut Saturator),
    {
        f(&mut self.left);
        f(&mut self.right);
    }

    pub fn left_mut(&mut self) -> &mut Saturator {
        &mut self.left
    }

    pub fn right_mut(&mut self) -> &mut Saturator {
        &mut self.right
    }
}

impl Processor for StereoSaturator {
    fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

impl StereoProcessor for StereoSaturator {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (
            self.left.process_sample(left),
            self.right.process_sample(right),
        )
    }
}

impl ProcessorConfig for StereoSaturator {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.left.set_sample_rate(sample_rate);
        self.right.set_sample_rate(sample_rate);
    }
}

/// Waveshaper with custom transfer function
#[derive(Debug, Clone)]
pub struct Waveshaper {
    /// Lookup table for transfer function
    table: Vec<Sample>,
    table_size: usize,
    drive: f64,
    mix: f64,
}

impl Waveshaper {
    pub fn new() -> Self {
        let table_size = 4096;
        let mut shaper = Self {
            table: vec![0.0; table_size],
            table_size,
            drive: 1.0,
            mix: 1.0,
        };
        shaper.set_curve(WaveshaperCurve::Tanh);
        shaper
    }

    /// Set predefined curve
    pub fn set_curve(&mut self, curve: WaveshaperCurve) {
        let n = self.table_size;
        for i in 0..n {
            let x = (i as f64 / (n - 1) as f64) * 2.0 - 1.0; // -1 to 1
            self.table[i] = match curve {
                WaveshaperCurve::Tanh => x.tanh(),
                WaveshaperCurve::Atan => (x * PI * 0.5).atan() / (PI * 0.5).atan(),
                WaveshaperCurve::Sine => (x * PI * 0.5).sin(),
                WaveshaperCurve::Cubic => x - x.powi(3) / 3.0,
                WaveshaperCurve::Asymmetric => {
                    if x >= 0.0 {
                        1.0 - (-x * 3.0).exp()
                    } else {
                        -(1.0 - (x * 2.0).exp())
                    }
                }
            };
        }
    }

    /// Set custom transfer function via closure
    pub fn set_custom_curve<F>(&mut self, f: F)
    where
        F: Fn(f64) -> f64,
    {
        let n = self.table_size;
        for i in 0..n {
            let x = (i as f64 / (n - 1) as f64) * 2.0 - 1.0;
            self.table[i] = f(x);
        }
    }

    pub fn set_drive(&mut self, drive: f64) {
        self.drive = drive.clamp(0.1, 100.0);
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Lookup with linear interpolation
    #[inline]
    fn lookup(&self, x: f64) -> Sample {
        // Clamp and scale to table range
        let clamped = x.clamp(-1.0, 1.0);
        let scaled = (clamped + 1.0) * 0.5 * (self.table_size - 1) as f64;

        let index = scaled as usize;
        let frac = scaled - index as f64;

        if index >= self.table_size - 1 {
            self.table[self.table_size - 1]
        } else {
            self.table[index] * (1.0 - frac) + self.table[index + 1] * frac
        }
    }
}

impl Default for Waveshaper {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for Waveshaper {
    fn reset(&mut self) {}
}

impl MonoProcessor for Waveshaper {
    #[inline]
    fn process_sample(&mut self, input: Sample) -> Sample {
        let driven = input * self.drive;
        let shaped = self.lookup(driven);
        input * (1.0 - self.mix) + shaped * self.mix
    }
}

/// Predefined waveshaper curves
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum WaveshaperCurve {
    Tanh,
    Atan,
    Sine,
    Cubic,
    Asymmetric,
}

/// Bit crusher (lo-fi effect)
#[derive(Debug, Clone)]
pub struct BitCrusher {
    bits: u32,
    sample_rate_reduction: f64,
    hold_counter: f64,
    held_sample: Sample,
    original_sample_rate: f64,
}

impl BitCrusher {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            bits: 16,
            sample_rate_reduction: 1.0,
            hold_counter: 0.0,
            held_sample: 0.0,
            original_sample_rate: sample_rate,
        }
    }

    /// Set bit depth (1-16)
    pub fn set_bits(&mut self, bits: u32) {
        self.bits = bits.clamp(1, 16);
    }

    /// Set sample rate reduction factor (1.0 = no reduction)
    pub fn set_sample_rate_reduction(&mut self, factor: f64) {
        self.sample_rate_reduction = factor.clamp(1.0, 100.0);
    }
}

impl Processor for BitCrusher {
    fn reset(&mut self) {
        self.hold_counter = 0.0;
        self.held_sample = 0.0;
    }
}

impl MonoProcessor for BitCrusher {
    #[inline]
    fn process_sample(&mut self, input: Sample) -> Sample {
        // Sample rate reduction (sample and hold)
        self.hold_counter += 1.0;
        if self.hold_counter >= self.sample_rate_reduction {
            self.hold_counter -= self.sample_rate_reduction;

            // Bit depth reduction
            let levels = (1u32 << self.bits) as f64;
            let quantized = (input * levels / 2.0).round() / (levels / 2.0);
            self.held_sample = quantized;
        }

        self.held_sample
    }
}

impl ProcessorConfig for BitCrusher {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.original_sample_rate = sample_rate;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OVERSAMPLED SATURATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Stereo saturator with oversampling for alias-free processing
///
/// Nonlinear processing (saturation, distortion) generates harmonics that can
/// alias back into the audible range. Oversampling prevents this by:
/// 1. Upsampling the input signal
/// 2. Processing at higher sample rate
/// 3. Lowpass filtering and downsampling
///
/// # Example
/// ```ignore
/// let mut sat = OversampledSaturator::new(48000.0, OversampleFactor::X4);
/// sat.set_type(SaturationType::Tube);
/// sat.set_drive_db(12.0);
/// sat.process(&mut left, &mut right);
/// ```
#[derive(Debug, Clone)]
pub struct OversampledSaturator {
    /// Inner saturator (processes at oversampled rate)
    saturator: StereoSaturator,
    /// Oversampler handles up/down conversion
    oversampler: GlobalOversampler,
    /// Original sample rate
    sample_rate: f64,
    /// Oversampling factor
    os_factor: OversampleFactor,
}

impl OversampledSaturator {
    /// Create oversampled saturator with given factor
    pub fn new(sample_rate: f64, factor: OversampleFactor) -> Self {
        // Saturator runs at oversampled rate
        let os_rate = sample_rate * factor.factor() as f64;
        Self {
            saturator: StereoSaturator::new(os_rate),
            oversampler: GlobalOversampler::new(factor, OversampleQuality::Standard),
            sample_rate,
            os_factor: factor,
        }
    }

    /// Create 4x oversampled saturator (good default for most cases)
    pub fn x4(sample_rate: f64) -> Self {
        Self::new(sample_rate, OversampleFactor::X4)
    }

    /// Create 8x oversampled saturator (high quality, more CPU)
    pub fn x8(sample_rate: f64) -> Self {
        Self::new(sample_rate, OversampleFactor::X8)
    }

    /// Set saturation type
    pub fn set_type(&mut self, sat_type: SaturationType) {
        self.saturator.set_both(|s| s.set_type(sat_type));
    }

    /// Set drive in dB
    pub fn set_drive_db(&mut self, db: f64) {
        self.saturator.set_both(|s| s.set_drive_db(db));
    }

    /// Set drive as linear gain
    pub fn set_drive(&mut self, drive: f64) {
        self.saturator.set_both(|s| s.set_drive(drive));
    }

    /// Set dry/wet mix (0.0 = dry, 1.0 = wet)
    pub fn set_mix(&mut self, mix: f64) {
        self.saturator.set_both(|s| s.set_mix(mix));
    }

    /// Set output level in dB
    pub fn set_output_db(&mut self, db: f64) {
        self.saturator.set_both(|s| s.set_output_db(db));
    }

    /// Set tape bias (only affects Tape mode)
    pub fn set_tape_bias(&mut self, bias: f64) {
        self.saturator.set_both(|s| s.set_tape_bias(bias));
    }

    /// Set oversampling factor
    pub fn set_oversample_factor(&mut self, factor: OversampleFactor) {
        if factor != self.os_factor {
            self.os_factor = factor;
            self.oversampler.set_factor(factor);
            // Update saturator sample rate
            let os_rate = self.sample_rate * factor.factor() as f64;
            self.saturator.left_mut().set_sample_rate(os_rate);
            self.saturator.right_mut().set_sample_rate(os_rate);
        }
    }

    /// Get latency in samples (for delay compensation)
    pub fn latency(&self) -> usize {
        self.oversampler.latency()
    }

    /// Process stereo buffer with oversampling
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        // Capture mutable reference to saturator for closure
        let saturator = &mut self.saturator;

        self.oversampler.process(left, right, |os_l, os_r| {
            // Process each sample at oversampled rate
            for i in 0..os_l.len() {
                let (out_l, out_r) = saturator.process_sample(os_l[i], os_r[i]);
                os_l[i] = out_l;
                os_r[i] = out_r;
            }
        });
    }

    /// Access inner saturator for advanced configuration
    pub fn inner_mut(&mut self) -> &mut StereoSaturator {
        &mut self.saturator
    }
}

impl Processor for OversampledSaturator {
    fn reset(&mut self) {
        self.saturator.reset();
        self.oversampler.reset();
    }
}

impl ProcessorConfig for OversampledSaturator {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        let os_rate = sample_rate * self.os_factor.factor() as f64;
        self.saturator.left_mut().set_sample_rate(os_rate);
        self.saturator.right_mut().set_sample_rate(os_rate);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MULTIBAND SATURATOR (Saturn 2 class)
// ═══════════════════════════════════════════════════════════════════════════════

use crate::biquad::BiquadCoeffs;
use crate::multiband::{CrossoverType, MAX_BANDS};

/// Per-band saturation settings
#[derive(Debug, Clone)]
pub struct BandSaturator {
    /// Inner saturator (oversampled)
    saturator: OversampledSaturator,
    /// Drive (dB)
    pub drive_db: f64,
    /// Saturation type
    pub sat_type: SaturationType,
    /// Tone control (-100 to +100)
    pub tone: f64,
    /// Mix (0..1)
    pub mix: f64,
    /// Output gain (dB)
    pub output_db: f64,
    /// Solo this band
    pub solo: bool,
    /// Mute this band
    pub mute: bool,
    /// Bypass saturation (pass-through)
    pub bypass: bool,
    /// Dynamics: compand amount (0 = off, positive = upward, negative = downward)
    pub dynamics: f64,
    // Envelope for dynamics
    envelope: f64,
}

impl BandSaturator {
    pub fn new(sample_rate: f64) -> Self {
        let mut sat = OversampledSaturator::new(sample_rate, OversampleFactor::X2);
        sat.set_drive_db(0.0);
        sat.set_mix(1.0);
        sat.set_output_db(0.0);
        Self {
            saturator: sat,
            drive_db: 0.0,
            sat_type: SaturationType::Tape,
            tone: 0.0,
            mix: 1.0,
            output_db: 0.0,
            solo: false,
            mute: false,
            bypass: false,
            dynamics: 0.0,
            envelope: 0.0,
        }
    }

    pub fn set_drive_db(&mut self, db: f64) {
        self.drive_db = db.clamp(-24.0, 40.0);
        self.saturator.set_drive_db(self.drive_db);
    }

    pub fn set_type(&mut self, sat_type: SaturationType) {
        self.sat_type = sat_type;
        self.saturator.set_type(sat_type);
    }

    pub fn set_tone(&mut self, tone: f64) {
        self.tone = tone.clamp(-100.0, 100.0);
        let bias = (0.5 + tone / 100.0 * 0.3).clamp(0.0, 1.0);
        self.saturator.set_tape_bias(bias);
    }

    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
        self.saturator.set_mix(self.mix);
    }

    pub fn set_output_db(&mut self, db: f64) {
        self.output_db = db.clamp(-24.0, 24.0);
        self.saturator.set_output_db(self.output_db);
    }

    pub fn set_oversample_factor(&mut self, factor: OversampleFactor) {
        self.saturator.set_oversample_factor(factor);
    }

    /// Process a stereo buffer through this band's saturator
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        if self.mute {
            for s in left.iter_mut() {
                *s = 0.0;
            }
            for s in right.iter_mut() {
                *s = 0.0;
            }
            return;
        }
        if self.bypass {
            return;
        }

        // Dynamics processing (modulate drive based on level)
        if self.dynamics.abs() > 0.01 {
            for i in 0..left.len().min(right.len()) {
                let level = (left[i].abs() + right[i].abs()) * 0.5;
                // Smooth envelope
                let coef = if level > self.envelope { 0.1 } else { 0.995 };
                self.envelope = level + coef * (self.envelope - level);
                // Modulate drive: positive dynamics = more drive on louder signals
                let env_db = if self.envelope > 1e-10 {
                    20.0 * self.envelope.log10()
                } else {
                    -60.0
                };
                let drive_mod = self.dynamics * (env_db + 20.0) / 40.0; // normalized
                let effective_drive = self.drive_db + drive_mod * 12.0; // up to ±12dB modulation
                // Apply per-sample drive (approximate — set once per block chunk)
                if i == 0 {
                    self.saturator
                        .set_drive_db(effective_drive.clamp(-24.0, 52.0));
                }
            }
        }

        self.saturator.process(left, right);

        // Restore drive if dynamics was active
        if self.dynamics.abs() > 0.01 {
            self.saturator.set_drive_db(self.drive_db);
        }
    }

    pub fn reset(&mut self) {
        self.saturator.reset();
        self.envelope = 0.0;
    }

    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.saturator.set_sample_rate(sample_rate);
    }

    pub fn latency(&self) -> usize {
        self.saturator.latency()
    }
}

/// Linkwitz-Riley stereo crossover filter for multiband splitting
#[derive(Debug, Clone)]
struct MbCrossover {
    lp_l: Vec<crate::biquad::BiquadTDF2>,
    lp_r: Vec<crate::biquad::BiquadTDF2>,
    hp_l: Vec<crate::biquad::BiquadTDF2>,
    hp_r: Vec<crate::biquad::BiquadTDF2>,
    frequency: f64,
}

impl MbCrossover {
    fn new(freq: f64, sample_rate: f64, crossover_type: CrossoverType) -> Self {
        let num_stages = crossover_type.order() / 2;
        let q = std::f64::consts::FRAC_1_SQRT_2;

        let make_stages = |is_lowpass: bool| -> Vec<crate::biquad::BiquadTDF2> {
            (0..num_stages)
                .map(|_| {
                    let coeffs = if is_lowpass {
                        BiquadCoeffs::lowpass(freq, q, sample_rate)
                    } else {
                        BiquadCoeffs::highpass(freq, q, sample_rate)
                    };
                    crate::biquad::BiquadTDF2::with_coeffs(coeffs, sample_rate)
                })
                .collect()
        };

        Self {
            lp_l: make_stages(true),
            lp_r: make_stages(true),
            hp_l: make_stages(false),
            hp_r: make_stages(false),
            frequency: freq,
        }
    }

    fn split(&mut self, left: f64, right: f64) -> ((f64, f64), (f64, f64)) {
        let mut low_l = left;
        let mut low_r = right;
        let mut high_l = left;
        let mut high_r = right;
        for stage in &mut self.lp_l {
            low_l = stage.process_sample(low_l);
        }
        for stage in &mut self.lp_r {
            low_r = stage.process_sample(low_r);
        }
        for stage in &mut self.hp_l {
            high_l = stage.process_sample(high_l);
        }
        for stage in &mut self.hp_r {
            high_r = stage.process_sample(high_r);
        }
        ((low_l, low_r), (high_l, high_r))
    }

    fn reset(&mut self) {
        for s in &mut self.lp_l {
            s.reset();
        }
        for s in &mut self.lp_r {
            s.reset();
        }
        for s in &mut self.hp_l {
            s.reset();
        }
        for s in &mut self.hp_r {
            s.reset();
        }
    }

    fn set_frequency(&mut self, freq: f64, sample_rate: f64) {
        self.frequency = freq;
        let q = std::f64::consts::FRAC_1_SQRT_2;
        let lp_coeffs = BiquadCoeffs::lowpass(freq, q, sample_rate);
        let hp_coeffs = BiquadCoeffs::highpass(freq, q, sample_rate);
        for s in &mut self.lp_l {
            s.set_coeffs(lp_coeffs);
        }
        for s in &mut self.lp_r {
            s.set_coeffs(lp_coeffs);
        }
        for s in &mut self.hp_l {
            s.set_coeffs(hp_coeffs);
        }
        for s in &mut self.hp_r {
            s.set_coeffs(hp_coeffs);
        }
    }
}

/// Default crossover frequencies for multiband saturator
const MB_SAT_DEFAULT_CROSSOVERS: [f64; 5] = [120.0, 750.0, 2500.0, 7000.0, 14000.0];

/// Multiband saturator — Saturn 2 class
///
/// Up to 6 bands, each with independent saturation type, drive, tone, mix, and dynamics.
/// Linkwitz-Riley crossover network ensures phase-coherent band splitting.
///
/// # Features
/// - Per-band saturation type (Tape, Tube, Transistor, SoftClip, HardClip, Foldback)
/// - Per-band drive, tone, mix, output gain
/// - Per-band dynamics (envelope-following drive modulation)
/// - Per-band solo/mute/bypass
/// - Oversampled processing per-band
/// - Global input/output gain and M/S processing
#[derive(Debug, Clone)]
pub struct MultibandSaturator {
    /// Number of active bands (2-6)
    num_bands: usize,
    /// Crossover filters
    crossovers: Vec<MbCrossover>,
    /// Per-band saturators
    bands: Vec<BandSaturator>,
    /// Crossover frequencies
    crossover_freqs: Vec<f64>,
    /// Crossover filter type
    crossover_type: CrossoverType,
    /// Global input gain (dB)
    input_gain_db: f64,
    /// Global output gain (dB)
    output_gain_db: f64,
    /// Global mix (0..1)
    global_mix: f64,
    /// M/S mode
    ms_mode: bool,
    /// Sample rate
    sample_rate: f64,
    /// Band buffers for splitting
    band_buffers_l: Vec<Vec<f64>>,
    band_buffers_r: Vec<Vec<f64>>,
}

impl MultibandSaturator {
    /// Create a new multiband saturator
    pub fn new(sample_rate: f64, num_bands: usize) -> Self {
        let num_bands = num_bands.clamp(2, MAX_BANDS);
        let num_crossovers = num_bands - 1;

        let crossover_freqs: Vec<f64> = MB_SAT_DEFAULT_CROSSOVERS[..num_crossovers].to_vec();
        let crossover_type = CrossoverType::LinkwitzRiley24;

        let crossovers: Vec<MbCrossover> = crossover_freqs
            .iter()
            .map(|&freq| MbCrossover::new(freq, sample_rate, crossover_type))
            .collect();

        let bands: Vec<BandSaturator> = (0..num_bands)
            .map(|_| BandSaturator::new(sample_rate))
            .collect();

        Self {
            num_bands,
            crossovers,
            bands,
            crossover_freqs,
            crossover_type,
            input_gain_db: 0.0,
            output_gain_db: 0.0,
            global_mix: 1.0,
            ms_mode: false,
            sample_rate,
            band_buffers_l: vec![Vec::new(); num_bands],
            band_buffers_r: vec![Vec::new(); num_bands],
        }
    }

    /// Set number of bands (2-6)
    pub fn set_num_bands(&mut self, num_bands: usize) {
        let num_bands = num_bands.clamp(2, MAX_BANDS);
        if num_bands == self.num_bands {
            return;
        }
        self.num_bands = num_bands;
        let num_crossovers = num_bands - 1;

        self.crossover_freqs = MB_SAT_DEFAULT_CROSSOVERS[..num_crossovers].to_vec();
        self.crossovers = self
            .crossover_freqs
            .iter()
            .map(|&freq| MbCrossover::new(freq, self.sample_rate, self.crossover_type))
            .collect();
        self.bands
            .resize_with(num_bands, || BandSaturator::new(self.sample_rate));
        self.band_buffers_l = vec![Vec::new(); num_bands];
        self.band_buffers_r = vec![Vec::new(); num_bands];
    }

    /// Set crossover frequency at index
    pub fn set_crossover(&mut self, index: usize, freq: f64) {
        if index < self.crossovers.len() {
            let freq = freq.clamp(20.0, 20000.0);
            self.crossover_freqs[index] = freq;
            self.crossovers[index].set_frequency(freq, self.sample_rate);
        }
    }

    /// Get band reference
    pub fn band(&self, index: usize) -> Option<&BandSaturator> {
        self.bands.get(index)
    }

    /// Get mutable band reference
    pub fn band_mut(&mut self, index: usize) -> Option<&mut BandSaturator> {
        self.bands.get_mut(index)
    }

    /// Number of active bands
    pub fn num_bands(&self) -> usize {
        self.num_bands
    }

    pub fn set_input_gain_db(&mut self, db: f64) {
        self.input_gain_db = db.clamp(-24.0, 24.0);
    }

    pub fn set_output_gain_db(&mut self, db: f64) {
        self.output_gain_db = db.clamp(-24.0, 24.0);
    }

    pub fn set_global_mix(&mut self, mix: f64) {
        self.global_mix = mix.clamp(0.0, 1.0);
    }

    pub fn set_ms_mode(&mut self, ms: bool) {
        self.ms_mode = ms;
    }

    pub fn set_crossover_type(&mut self, crossover_type: CrossoverType) {
        self.crossover_type = crossover_type;
        self.crossovers = self
            .crossover_freqs
            .iter()
            .map(|&freq| MbCrossover::new(freq, self.sample_rate, crossover_type))
            .collect();
    }

    /// Process stereo buffers through multiband saturation
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let len = left.len().min(right.len());
        if len == 0 {
            return;
        }

        // Save dry signal for global mix
        let dry_l: Vec<f64> = left[..len].to_vec();
        let dry_r: Vec<f64> = right[..len].to_vec();

        // Input gain
        let in_gain = 10.0_f64.powf(self.input_gain_db / 20.0);
        if (in_gain - 1.0).abs() > 0.001 {
            for i in 0..len {
                left[i] *= in_gain;
                right[i] *= in_gain;
            }
        }

        // M/S encode
        if self.ms_mode {
            for i in 0..len {
                let mid = (left[i] + right[i]) * 0.5;
                let side = (left[i] - right[i]) * 0.5;
                left[i] = mid;
                right[i] = side;
            }
        }

        // Ensure band buffers are sized
        for b in 0..self.num_bands {
            self.band_buffers_l[b].resize(len, 0.0);
            self.band_buffers_r[b].resize(len, 0.0);
        }

        // Split into bands (sample-by-sample crossover, fill buffers)
        for i in 0..len {
            let mut rem_l = left[i];
            let mut rem_r = right[i];
            for c in 0..self.crossovers.len() {
                let ((low_l, low_r), (high_l, high_r)) =
                    self.crossovers[c].split(rem_l, rem_r);
                self.band_buffers_l[c][i] = low_l;
                self.band_buffers_r[c][i] = low_r;
                rem_l = high_l;
                rem_r = high_r;
            }
            // Last band = remaining highs
            self.band_buffers_l[self.num_bands - 1][i] = rem_l;
            self.band_buffers_r[self.num_bands - 1][i] = rem_r;
        }

        // Process each band through its saturator
        let any_solo = self.bands.iter().any(|b| b.solo);

        // Zero output
        for i in 0..len {
            left[i] = 0.0;
            right[i] = 0.0;
        }

        for b in 0..self.num_bands {
            // Skip if another band is solo'd and this one isn't
            if any_solo && !self.bands[b].solo {
                continue;
            }

            self.bands[b].process(&mut self.band_buffers_l[b], &mut self.band_buffers_r[b]);

            // Sum bands
            for i in 0..len {
                left[i] += self.band_buffers_l[b][i];
                right[i] += self.band_buffers_r[b][i];
            }
        }

        // M/S decode
        if self.ms_mode {
            for i in 0..len {
                let l = left[i] + right[i];
                let r = left[i] - right[i];
                left[i] = l;
                right[i] = r;
            }
        }

        // Output gain
        let out_gain = 10.0_f64.powf(self.output_gain_db / 20.0);

        // Global mix + output gain
        for i in 0..len {
            left[i] = dry_l[i] * (1.0 - self.global_mix) + left[i] * self.global_mix;
            right[i] = dry_r[i] * (1.0 - self.global_mix) + right[i] * self.global_mix;
            left[i] *= out_gain;
            right[i] *= out_gain;
        }
    }

    pub fn reset(&mut self) {
        for c in &mut self.crossovers {
            c.reset();
        }
        for b in &mut self.bands {
            b.reset();
        }
    }

    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for (i, c) in self.crossovers.iter_mut().enumerate() {
            c.set_frequency(self.crossover_freqs[i], sample_rate);
        }
        for b in &mut self.bands {
            b.set_sample_rate(sample_rate);
        }
    }

    pub fn latency(&self) -> usize {
        // Max latency across bands
        self.bands.iter().map(|b| b.latency()).max().unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_saturator_types() {
        for sat_type in [
            SaturationType::Tape,
            SaturationType::Tube,
            SaturationType::Transistor,
            SaturationType::SoftClip,
            SaturationType::HardClip,
            SaturationType::Foldback,
        ] {
            let mut sat = Saturator::new(48000.0);
            sat.set_type(sat_type);
            sat.set_drive(2.0);

            // Process some samples
            for i in 0..100 {
                let input = (i as f64 * 0.1).sin();
                let output = sat.process_sample(input);

                // Output should be finite
                assert!(output.is_finite());

                // Soft/hard clip should limit to ±1
                if matches!(
                    sat_type,
                    SaturationType::SoftClip | SaturationType::HardClip
                ) {
                    assert!(output.abs() <= 1.1); // Small margin for soft clip
                }
            }
        }
    }

    #[test]
    fn test_waveshaper() {
        let mut shaper = Waveshaper::new();
        shaper.set_curve(WaveshaperCurve::Tanh);
        shaper.set_drive(2.0);

        // Should saturate
        let output = shaper.process_sample(1.0);
        assert!(output < 1.0);
        assert!(output > 0.5);
    }

    #[test]
    fn test_bitcrusher() {
        let mut crusher = BitCrusher::new(48000.0);
        crusher.set_bits(4);
        crusher.set_sample_rate_reduction(8.0);

        // Process sine wave
        let mut outputs = Vec::new();
        for i in 0..100 {
            let input = (i as f64 * 0.1).sin();
            outputs.push(crusher.process_sample(input));
        }

        // Should have step-like output (sample and hold)
        let mut step_count = 0;
        for i in 1..outputs.len() {
            if (outputs[i] - outputs[i - 1]).abs() < 1e-10 {
                step_count += 1;
            }
        }
        assert!(step_count > 50); // Many samples should be held
    }

    #[test]
    fn test_oversampled_saturator() {
        let mut sat = OversampledSaturator::x4(48000.0);
        sat.set_type(SaturationType::Tube);
        sat.set_drive_db(12.0);

        // Generate test signal (1kHz sine)
        let len = 256;
        let mut left: Vec<f64> = (0..len)
            .map(|i| (2.0 * PI * 1000.0 * i as f64 / 48000.0).sin() * 0.5)
            .collect();
        let mut right = left.clone();

        // Process
        sat.process(&mut left, &mut right);

        // Check outputs are valid
        for i in 0..len {
            assert!(left[i].is_finite(), "Left sample {} not finite", i);
            assert!(right[i].is_finite(), "Right sample {} not finite", i);
            // Saturated output should be bounded
            assert!(
                left[i].abs() < 2.0,
                "Left sample {} too large: {}",
                i,
                left[i]
            );
        }
    }

    #[test]
    fn test_oversampled_saturator_latency() {
        let sat_x1 = OversampledSaturator::new(48000.0, OversampleFactor::X1);
        let sat_x4 = OversampledSaturator::x4(48000.0);
        let sat_x8 = OversampledSaturator::x8(48000.0);

        // X1 should have zero latency
        assert_eq!(sat_x1.latency(), 0);

        // X4 and X8 have positive latency
        assert!(sat_x4.latency() > 0, "X4 latency should be > 0");
        assert!(sat_x8.latency() > 0, "X8 latency should be > 0");

        // Verify latency values match oversampler calculation
        // (filter_order / factor gives taps_per_phase)
        assert_eq!(sat_x4.latency(), 16); // 64 / 4 = 16
        assert_eq!(sat_x8.latency(), 12); // 96 / 8 = 12
    }
}
