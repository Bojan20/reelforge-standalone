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
}
