//! Spatial audio processing
//!
//! Includes:
//! - Stereo panner (multiple pan laws)
//! - Stereo width control
//! - Mid/Side processing
//! - Stereo rotation
//! - Binaural processing basics

use rf_core::Sample;
use std::f64::consts::PI;

use crate::{Processor, ProcessorConfig, StereoProcessor};

/// Pan law types
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum PanLaw {
    /// Linear panning: -6dB center
    Linear,
    /// Constant power: -3dB center (most common)
    #[default]
    ConstantPower,
    /// Compromise: -4.5dB center
    Compromise,
    /// No attenuation at center (mono compatible)
    NoCenterAttenuation,
}

/// Stereo panner with multiple pan laws
#[derive(Debug, Clone)]
pub struct StereoPanner {
    pan: f64, // -1.0 (left) to 1.0 (right), 0.0 = center
    pan_law: PanLaw,

    // Cached gains
    gain_l: f64,
    gain_r: f64,
}

impl StereoPanner {
    pub fn new() -> Self {
        let mut panner = Self {
            pan: 0.0,
            pan_law: PanLaw::ConstantPower,
            gain_l: 1.0,
            gain_r: 1.0,
        };
        panner.update_gains();
        panner
    }

    /// Set pan position (-1.0 = left, 0.0 = center, 1.0 = right)
    pub fn set_pan(&mut self, pan: f64) {
        self.pan = pan.clamp(-1.0, 1.0);
        self.update_gains();
    }

    /// Set pan law
    pub fn set_pan_law(&mut self, law: PanLaw) {
        self.pan_law = law;
        self.update_gains();
    }

    /// Get current pan position
    pub fn pan(&self) -> f64 {
        self.pan
    }

    /// Update cached gains based on pan position and law
    fn update_gains(&mut self) {
        let pan_angle = (self.pan + 1.0) * 0.5 * PI * 0.5; // 0 to PI/4

        match self.pan_law {
            PanLaw::Linear => {
                // Linear: simple crossfade, -6dB at center
                self.gain_l = 1.0 - (self.pan + 1.0) * 0.5;
                self.gain_r = (self.pan + 1.0) * 0.5;
            }
            PanLaw::ConstantPower => {
                // Constant power: -3dB at center
                self.gain_l = pan_angle.cos();
                self.gain_r = pan_angle.sin();
            }
            PanLaw::Compromise => {
                // Compromise: blend of linear and constant power (-4.5dB)
                let linear_l = 1.0 - (self.pan + 1.0) * 0.5;
                let linear_r = (self.pan + 1.0) * 0.5;
                let cp_l = pan_angle.cos();
                let cp_r = pan_angle.sin();
                self.gain_l = (linear_l + cp_l) * 0.5;
                self.gain_r = (linear_r + cp_r) * 0.5;
            }
            PanLaw::NoCenterAttenuation => {
                // No attenuation at center, attenuate hard pans
                if self.pan < 0.0 {
                    self.gain_l = 1.0;
                    self.gain_r = 1.0 + self.pan;
                } else {
                    self.gain_l = 1.0 - self.pan;
                    self.gain_r = 1.0;
                }
            }
        }
    }
}

impl Default for StereoPanner {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for StereoPanner {
    fn reset(&mut self) {
        // Stateless, nothing to reset
    }
}

impl StereoProcessor for StereoPanner {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Mono input panning
        let mono = (left + right) * 0.5;
        (mono * self.gain_l, mono * self.gain_r)
    }
}

/// Stereo balance (preserves stereo image, adjusts L/R level)
#[derive(Debug, Clone)]
pub struct StereoBalance {
    balance: f64, // -1.0 to 1.0
    gain_l: f64,
    gain_r: f64,
}

impl StereoBalance {
    pub fn new() -> Self {
        Self {
            balance: 0.0,
            gain_l: 1.0,
            gain_r: 1.0,
        }
    }

    pub fn set_balance(&mut self, balance: f64) {
        self.balance = balance.clamp(-1.0, 1.0);

        // Calculate gains
        if self.balance < 0.0 {
            self.gain_l = 1.0;
            self.gain_r = 1.0 + self.balance;
        } else {
            self.gain_l = 1.0 - self.balance;
            self.gain_r = 1.0;
        }
    }
}

impl Default for StereoBalance {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for StereoBalance {
    fn reset(&mut self) {}
}

impl StereoProcessor for StereoBalance {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (left * self.gain_l, right * self.gain_r)
    }
}

/// Stereo width control
#[derive(Debug, Clone)]
pub struct StereoWidth {
    width: f64, // 0.0 = mono, 1.0 = stereo, 2.0 = extra wide
}

impl StereoWidth {
    pub fn new() -> Self {
        Self { width: 1.0 }
    }

    /// Set width (0.0 = mono, 1.0 = original, 2.0 = extra wide)
    pub fn set_width(&mut self, width: f64) {
        self.width = width.clamp(0.0, 2.0);
    }

    pub fn width(&self) -> f64 {
        self.width
    }
}

impl Default for StereoWidth {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for StereoWidth {
    fn reset(&mut self) {}
}

impl StereoProcessor for StereoWidth {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Convert to M/S
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;

        // Apply width to side signal
        let side_scaled = side * self.width;

        // Convert back to L/R
        (mid + side_scaled, mid - side_scaled)
    }
}

/// Mid/Side encoder
#[derive(Debug, Clone, Copy)]
pub struct MsEncoder;

impl MsEncoder {
    /// Convert L/R to M/S
    #[inline]
    pub fn encode(left: Sample, right: Sample) -> (Sample, Sample) {
        let mid = (left + right) * 0.5;
        let side = (left - right) * 0.5;
        (mid, side)
    }

    /// Convert M/S to L/R
    #[inline]
    pub fn decode(mid: Sample, side: Sample) -> (Sample, Sample) {
        let left = mid + side;
        let right = mid - side;
        (left, right)
    }
}

/// Full Mid/Side processor with separate M and S gains
#[derive(Debug, Clone)]
pub struct MsProcessor {
    mid_gain: f64,
    side_gain: f64,
}

impl MsProcessor {
    pub fn new() -> Self {
        Self {
            mid_gain: 1.0,
            side_gain: 1.0,
        }
    }

    pub fn set_mid_gain(&mut self, gain: f64) {
        self.mid_gain = gain.clamp(0.0, 2.0);
    }

    pub fn set_side_gain(&mut self, gain: f64) {
        self.side_gain = gain.clamp(0.0, 2.0);
    }

    pub fn set_mid_gain_db(&mut self, db: f64) {
        self.mid_gain = 10.0_f64.powf(db.clamp(-24.0, 12.0) / 20.0);
    }

    pub fn set_side_gain_db(&mut self, db: f64) {
        self.side_gain = 10.0_f64.powf(db.clamp(-24.0, 12.0) / 20.0);
    }
}

impl Default for MsProcessor {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for MsProcessor {
    fn reset(&mut self) {}
}

impl StereoProcessor for MsProcessor {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let (mid, side) = MsEncoder::encode(left, right);
        MsEncoder::decode(mid * self.mid_gain, side * self.side_gain)
    }
}

/// Stereo rotation (rotate stereo field)
#[derive(Debug, Clone)]
pub struct StereoRotation {
    angle: f64, // Radians
    cos_angle: f64,
    sin_angle: f64,
}

impl StereoRotation {
    pub fn new() -> Self {
        Self {
            angle: 0.0,
            cos_angle: 1.0,
            sin_angle: 0.0,
        }
    }

    /// Set rotation angle in degrees (-180 to 180)
    pub fn set_angle_degrees(&mut self, degrees: f64) {
        self.angle = degrees.clamp(-180.0, 180.0) * PI / 180.0;
        self.cos_angle = self.angle.cos();
        self.sin_angle = self.angle.sin();
    }

    /// Set rotation angle in radians
    pub fn set_angle(&mut self, radians: f64) {
        self.angle = radians;
        self.cos_angle = self.angle.cos();
        self.sin_angle = self.angle.sin();
    }
}

impl Default for StereoRotation {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor for StereoRotation {
    fn reset(&mut self) {}
}

impl StereoProcessor for StereoRotation {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // 2D rotation matrix
        let out_l = left * self.cos_angle - right * self.sin_angle;
        let out_r = left * self.sin_angle + right * self.cos_angle;
        (out_l, out_r)
    }
}

/// Stereo correlation meter
#[derive(Debug, Clone)]
pub struct CorrelationMeter {
    sum_lr: f64,
    sum_l2: f64,
    sum_r2: f64,
    decay: f64,
}

impl CorrelationMeter {
    pub fn new(sample_rate: f64) -> Self {
        // ~300ms averaging time
        let decay = (-1.0 / (0.3 * sample_rate)).exp();

        Self {
            sum_lr: 0.0,
            sum_l2: 0.0,
            sum_r2: 0.0,
            decay,
        }
    }

    /// Get current correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = correlated/mono)
    pub fn correlation(&self) -> f64 {
        let denominator = (self.sum_l2 * self.sum_r2).sqrt();
        if denominator > 1e-10 {
            (self.sum_lr / denominator).clamp(-1.0, 1.0)
        } else {
            0.0
        }
    }

    /// Process a sample pair and update correlation
    pub fn process(&mut self, left: Sample, right: Sample) {
        self.sum_lr = self.sum_lr * self.decay + left * right;
        self.sum_l2 = self.sum_l2 * self.decay + left * left;
        self.sum_r2 = self.sum_r2 * self.decay + right * right;
    }

    pub fn reset(&mut self) {
        self.sum_lr = 0.0;
        self.sum_l2 = 0.0;
        self.sum_r2 = 0.0;
    }
}

/// Complete stereo imaging processor
#[derive(Debug, Clone)]
pub struct StereoImager {
    // Processing chain
    pub balance: StereoBalance,
    pub panner: StereoPanner,
    pub width: StereoWidth,
    pub ms: MsProcessor,
    pub rotation: StereoRotation,

    // Metering
    pub correlation: CorrelationMeter,

    // Control flags
    use_balance: bool,
    use_panner: bool,
    use_width: bool,
    use_ms: bool,
    use_rotation: bool,
}

impl StereoImager {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            balance: StereoBalance::new(),
            panner: StereoPanner::new(),
            width: StereoWidth::new(),
            ms: MsProcessor::new(),
            rotation: StereoRotation::new(),
            correlation: CorrelationMeter::new(sample_rate),
            use_balance: false,
            use_panner: false,
            use_width: true,
            use_ms: false,
            use_rotation: false,
        }
    }

    pub fn enable_balance(&mut self, enabled: bool) {
        self.use_balance = enabled;
    }

    pub fn enable_panner(&mut self, enabled: bool) {
        self.use_panner = enabled;
    }

    pub fn enable_width(&mut self, enabled: bool) {
        self.use_width = enabled;
    }

    pub fn enable_ms(&mut self, enabled: bool) {
        self.use_ms = enabled;
    }

    pub fn enable_rotation(&mut self, enabled: bool) {
        self.use_rotation = enabled;
    }
}

impl Processor for StereoImager {
    fn reset(&mut self) {
        self.balance.reset();
        self.panner.reset();
        self.width.reset();
        self.ms.reset();
        self.rotation.reset();
        self.correlation.reset();
    }
}

impl StereoProcessor for StereoImager {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let (mut l, mut r) = (left, right);

        if self.use_balance {
            (l, r) = self.balance.process_sample(l, r);
        }

        if self.use_panner {
            (l, r) = self.panner.process_sample(l, r);
        }

        if self.use_width {
            (l, r) = self.width.process_sample(l, r);
        }

        if self.use_ms {
            (l, r) = self.ms.process_sample(l, r);
        }

        if self.use_rotation {
            (l, r) = self.rotation.process_sample(l, r);
        }

        // Update correlation meter
        self.correlation.process(l, r);

        (l, r)
    }
}

impl ProcessorConfig for StereoImager {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.correlation = CorrelationMeter::new(sample_rate);
    }
}

// ============ Haas Delay (Precedence Effect Stereo Widener) ============

/// Which channel receives the delay
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum HaasChannel {
    Left,
    Right,
}

/// Haas Delay — Precedence effect stereo widener
///
/// Delays one channel by 0.1-30ms to create a perceived stereo width
/// using the psychoacoustic precedence effect (Haas effect).
/// Includes LP filter for natural sound and optional feedback.
///
/// Parameters (7):
///   0: delay_ms       (0.1 - 30.0, default 8.0)
///   1: delayed_channel (0.0 = Left, 1.0 = Right, default 1.0)
///   2: mix            (0.0 - 1.0, default 1.0)
///   3: lp_enabled     (0.0 or 1.0, default 1.0)
///   4: lp_frequency   (200.0 - 18000.0 Hz, default 8000.0)
///   5: feedback       (0.0 - 0.7, default 0.0)
///   6: phase_invert   (0.0 or 1.0, default 0.0)
#[derive(Debug, Clone)]
pub struct HaasDelay {
    // Parameters
    delay_ms: f64,
    delayed_channel: HaasChannel,
    mix: f64,
    lp_enabled: bool,
    lp_frequency: f64,
    feedback: f64,
    phase_invert: bool,

    // Internal state
    sample_rate: f64,
    buffer: Vec<f64>,
    buffer_size: usize,
    write_pos: usize,
    delay_samples: f64,

    // One-pole LP filter state (simple, zero-latency)
    lp_z1: f64,
    lp_coeff: f64,

    // Feedback state
    feedback_sample: f64,
}

impl HaasDelay {
    pub fn new(sample_rate: f64) -> Self {
        // Max buffer = 30ms at max sample rate (192kHz) = ~5760 samples, use 8192 for safety
        let buffer_size = 8192;
        let mut hd = Self {
            delay_ms: 8.0,
            delayed_channel: HaasChannel::Right,
            mix: 1.0,
            lp_enabled: true,
            lp_frequency: 8000.0,
            feedback: 0.0,
            phase_invert: false,
            sample_rate,
            buffer: vec![0.0; buffer_size],
            buffer_size,
            write_pos: 0,
            delay_samples: 8.0 * sample_rate / 1000.0,
            lp_z1: 0.0,
            lp_coeff: 0.0,
            feedback_sample: 0.0,
        };
        hd.update_lp_coeff();
        hd
    }

    /// Set delay time in milliseconds (0.1 - 30.0)
    pub fn set_delay_ms(&mut self, ms: f64) {
        self.delay_ms = ms.clamp(0.1, 30.0);
        self.delay_samples = self.delay_ms * self.sample_rate / 1000.0;
    }

    /// Set which channel gets delayed
    pub fn set_delayed_channel(&mut self, channel: HaasChannel) {
        self.delayed_channel = channel;
    }

    /// Set dry/wet mix (0.0 = dry, 1.0 = full effect)
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Enable/disable low-pass filter on delayed signal
    pub fn set_lp_enabled(&mut self, enabled: bool) {
        self.lp_enabled = enabled;
    }

    /// Set LP filter frequency (200 - 18000 Hz)
    pub fn set_lp_frequency(&mut self, freq: f64) {
        self.lp_frequency = freq.clamp(200.0, 18000.0);
        self.update_lp_coeff();
    }

    /// Set feedback amount (0.0 - 0.7)
    pub fn set_feedback(&mut self, fb: f64) {
        self.feedback = fb.clamp(0.0, 0.7);
    }

    /// Set phase invert on delayed channel
    pub fn set_phase_invert(&mut self, invert: bool) {
        self.phase_invert = invert;
    }

    /// Update one-pole LP filter coefficient
    fn update_lp_coeff(&mut self) {
        // One-pole LP: y[n] = (1-a)*x[n] + a*y[n-1]
        // a = exp(-2*pi*fc/sr)
        let fc = self.lp_frequency.min(self.sample_rate * 0.49);
        self.lp_coeff = (-2.0 * PI * fc / self.sample_rate).exp();
    }

    /// Read from delay buffer with linear interpolation
    #[inline]
    fn read_delay(&self) -> f64 {
        let int_delay = self.delay_samples as usize;
        let frac = self.delay_samples - int_delay as f64;

        let idx0 = (self.write_pos + self.buffer_size - int_delay) % self.buffer_size;
        let idx1 = (self.write_pos + self.buffer_size - int_delay - 1) % self.buffer_size;

        // Linear interpolation for sub-sample accuracy
        self.buffer[idx0] * (1.0 - frac) + self.buffer[idx1] * frac
    }

    /// Write sample to delay buffer
    #[inline]
    fn write_delay(&mut self, sample: f64) {
        self.buffer[self.write_pos] = sample + self.feedback_sample * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.buffer_size;
    }

    /// Apply one-pole LP filter
    #[inline]
    fn apply_lp(&mut self, sample: f64) -> f64 {
        if self.lp_enabled {
            self.lp_z1 = sample * (1.0 - self.lp_coeff) + self.lp_z1 * self.lp_coeff;
            self.lp_z1
        } else {
            sample
        }
    }

    /// Process a single stereo sample pair
    #[inline]
    pub fn process_sample_stereo(&mut self, left: f64, right: f64) -> (f64, f64) {
        match self.delayed_channel {
            HaasChannel::Left => {
                // Delay left channel
                self.write_delay(left);
                let delayed = self.read_delay();
                let filtered = self.apply_lp(delayed);
                self.feedback_sample = filtered;

                let wet = if self.phase_invert { -filtered } else { filtered };
                let out_l = left * (1.0 - self.mix) + wet * self.mix;
                (out_l, right)
            }
            HaasChannel::Right => {
                // Delay right channel
                self.write_delay(right);
                let delayed = self.read_delay();
                let filtered = self.apply_lp(delayed);
                self.feedback_sample = filtered;

                let wet = if self.phase_invert { -filtered } else { filtered };
                let out_r = right * (1.0 - self.mix) + wet * self.mix;
                (left, out_r)
            }
        }
    }
}

impl Processor for HaasDelay {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.lp_z1 = 0.0;
        self.feedback_sample = 0.0;
    }
}

impl StereoProcessor for HaasDelay {
    #[inline]
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        self.process_sample_stereo(left, right)
    }
}

impl ProcessorConfig for HaasDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.delay_samples = self.delay_ms * sample_rate / 1000.0;
        self.update_lp_coeff();
        self.reset();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_panner_center() {
        let mut panner = StereoPanner::new();
        panner.set_pan(0.0);
        panner.set_pan_law(PanLaw::ConstantPower);

        let (l, r) = panner.process_sample(1.0, 1.0);

        // Should be equal level at center
        assert!((l - r).abs() < 0.01);
    }

    #[test]
    fn test_panner_hard_left() {
        let mut panner = StereoPanner::new();
        panner.set_pan(-1.0);

        let (l, r) = panner.process_sample(1.0, 1.0);

        // Should be mostly left
        assert!(l > r);
        assert!(r < 0.1);
    }

    #[test]
    fn test_stereo_width() {
        let mut width = StereoWidth::new();

        // Test mono (width = 0)
        width.set_width(0.0);
        let (l, r) = width.process_sample(1.0, -1.0); // Full side signal
        assert!((l - r).abs() < 0.01); // Should be mono

        // Test normal stereo (width = 1)
        width.set_width(1.0);
        let (l, r) = width.process_sample(1.0, -1.0);
        assert!((l - 1.0).abs() < 0.01);
        assert!((r - (-1.0)).abs() < 0.01);
    }

    #[test]
    fn test_ms_roundtrip() {
        let left = 0.7;
        let right = 0.3;

        let (mid, side) = MsEncoder::encode(left, right);
        let (l2, r2) = MsEncoder::decode(mid, side);

        assert!((left - l2).abs() < 1e-10);
        assert!((right - r2).abs() < 1e-10);
    }

    #[test]
    fn test_correlation_mono() {
        let mut meter = CorrelationMeter::new(48000.0);

        // Mono signal should have correlation = 1.0
        for _ in 0..1000 {
            meter.process(0.5, 0.5);
        }

        assert!(meter.correlation() > 0.95);
    }

    #[test]
    fn test_correlation_out_of_phase() {
        let mut meter = CorrelationMeter::new(48000.0);

        // Out of phase should have correlation = -1.0
        for _ in 0..1000 {
            meter.process(0.5, -0.5);
        }

        assert!(meter.correlation() < -0.95);
    }

    #[test]
    fn test_stereo_rotation() {
        let mut rotation = StereoRotation::new();
        rotation.set_angle_degrees(90.0);

        // 90 degree rotation should swap and invert
        let (l, r) = rotation.process_sample(1.0, 0.0);
        assert!(l.abs() < 0.01);
        assert!((r - 1.0).abs() < 0.01);
    }

    // ============ Haas Delay Tests ============

    #[test]
    fn test_haas_delay_right_channel() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_delay_ms(1.0); // 1ms = 48 samples at 48kHz
        haas.set_mix(1.0);
        haas.set_lp_enabled(false);
        haas.set_feedback(0.0);

        // Feed an impulse on right channel (sample 0)
        let (l, r) = haas.process_sample_stereo(0.0, 1.0);
        // At sample 0, delayed right should be near 0 (delay not reached yet)
        assert!((l - 0.0).abs() < 1e-6, "Left should be untouched");
        assert!(r.abs() < 0.01, "Right should be near-zero (delayed)");

        // Process enough samples for the impulse to emerge
        // 1ms at 48kHz = 48 samples. The impulse was written at sample 0,
        // so we need to advance 48 samples total.
        let mut found_impulse = false;
        for _ in 0..100 {
            let (_, r2) = haas.process_sample_stereo(0.0, 0.0);
            if r2.abs() > 0.3 {
                found_impulse = true;
                break;
            }
        }
        assert!(found_impulse, "Delayed impulse should appear within 100 samples (>2ms)");
    }

    #[test]
    fn test_haas_delay_left_channel() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_delay_ms(1.0);
        haas.set_delayed_channel(HaasChannel::Left);
        haas.set_mix(1.0);
        haas.set_lp_enabled(false);

        let (l, r) = haas.process_sample_stereo(1.0, 0.0);
        assert!(l.abs() < 0.01, "Left should be delayed");
        assert!((r - 0.0).abs() < 1e-6, "Right should be untouched");
    }

    #[test]
    fn test_haas_delay_passthrough_at_zero_mix() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_mix(0.0);

        // With mix=0, signal should pass through unchanged
        let (l, r) = haas.process_sample_stereo(0.7, 0.3);
        assert!((l - 0.7).abs() < 1e-10, "Left should be unchanged");
        assert!((r - 0.3).abs() < 1e-10, "Right should be unchanged");
    }

    #[test]
    fn test_haas_delay_phase_invert() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_delay_ms(0.1); // Minimum delay
        haas.set_mix(1.0);
        haas.set_lp_enabled(false);
        haas.set_phase_invert(true);

        // Feed constant signal
        for _ in 0..100 {
            haas.process_sample_stereo(0.0, 1.0);
        }
        let (_, r) = haas.process_sample_stereo(0.0, 1.0);
        // Phase inverted: should be negative
        assert!(r < -0.5, "Phase inverted delayed signal should be negative");
    }

    #[test]
    fn test_haas_delay_reset() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_delay_ms(1.0);
        haas.set_mix(1.0);
        haas.set_lp_enabled(false);

        // Fill buffer
        for _ in 0..100 {
            haas.process_sample_stereo(0.0, 1.0);
        }

        // Reset should clear buffer
        haas.reset();
        let (_, r) = haas.process_sample_stereo(0.0, 0.0);
        assert!(r.abs() < 1e-10, "After reset, output should be silent");
    }

    #[test]
    fn test_haas_delay_lp_filter() {
        let mut haas = HaasDelay::new(48000.0);
        haas.set_delay_ms(0.1);
        haas.set_mix(1.0);
        haas.set_lp_enabled(true);
        haas.set_lp_frequency(1000.0); // Very low LP — should attenuate high freq

        // The LP filter on the delayed signal should smooth the impulse
        haas.process_sample_stereo(0.0, 1.0);
        for _ in 0..10 {
            haas.process_sample_stereo(0.0, 0.0);
        }
        // LP filtered impulse should be spread out (lower peak)
        // Just verify no NaN/crash and output is reasonable
        let (_, r) = haas.process_sample_stereo(0.0, 0.0);
        assert!(r.is_finite(), "LP filtered output should be finite");
    }
}
