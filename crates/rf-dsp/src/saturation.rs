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
            assert!(left[i].abs() < 2.0, "Left sample {} too large: {}", i, left[i]);
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
