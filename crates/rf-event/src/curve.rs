//! Fade Curve Types
//!
//! Wwise/FMOD-compatible fade curves for volume transitions.

use serde::{Deserialize, Serialize};
use std::f32::consts::{E, FRAC_PI_2};

/// Fade curve type for volume transitions
///
/// Matches Dart UI `FadeCurve` enum exactly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum FadeCurve {
    /// Linear interpolation (constant rate)
    #[default]
    Linear = 0,
    /// Logarithmic curve (slow start, fast end) - 3dB
    Log3 = 1,
    /// Sine curve (smooth S)
    Sine = 2,
    /// Logarithmic curve (slow start, fast end) - 1dB
    Log1 = 3,
    /// Inverse S-curve (fast start/end, slow middle)
    InvSCurve = 4,
    /// S-curve (slow start/end, fast middle)
    SCurve = 5,
    /// Exponential curve (fast start, slow end) - 1dB
    Exp1 = 6,
    /// Exponential curve (fast start, slow end) - 3dB
    Exp3 = 7,
}

impl FadeCurve {
    /// Convert from u8 index
    #[inline]
    pub fn from_index(index: u8) -> Self {
        match index {
            0 => FadeCurve::Linear,
            1 => FadeCurve::Log3,
            2 => FadeCurve::Sine,
            3 => FadeCurve::Log1,
            4 => FadeCurve::InvSCurve,
            5 => FadeCurve::SCurve,
            6 => FadeCurve::Exp1,
            7 => FadeCurve::Exp3,
            _ => FadeCurve::Linear,
        }
    }

    /// Get display name
    pub fn name(&self) -> &'static str {
        match self {
            FadeCurve::Linear => "Linear",
            FadeCurve::Log3 => "Log3",
            FadeCurve::Sine => "Sine",
            FadeCurve::Log1 => "Log1",
            FadeCurve::InvSCurve => "InvSCurve",
            FadeCurve::SCurve => "SCurve",
            FadeCurve::Exp1 => "Exp1",
            FadeCurve::Exp3 => "Exp3",
        }
    }

    /// Evaluate curve at position t (0.0 - 1.0)
    ///
    /// Returns value in range 0.0 - 1.0
    #[inline]
    pub fn evaluate(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);

        match self {
            // Linear: y = t
            FadeCurve::Linear => t,

            // Logarithmic 3dB: slow start, fast end
            // y = ln(1 + t*3) / ln(4)
            FadeCurve::Log3 => (1.0 + t * 3.0).ln() / 4.0_f32.ln(),

            // Sine: smooth S using sine quarter period
            // y = sin(t * π/2)
            FadeCurve::Sine => (t * FRAC_PI_2).sin(),

            // Logarithmic 1dB: gentler log curve
            // y = ln(1 + t) / ln(2)
            FadeCurve::Log1 => (1.0 + t).ln() / 2.0_f32.ln(),

            // Inverse S-curve: fast at edges, slow in middle
            FadeCurve::InvSCurve => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - 2.0 * (1.0 - t) * (1.0 - t)
                }
            }

            // S-curve: slow at edges, fast in middle (cubic)
            FadeCurve::SCurve => {
                if t < 0.5 {
                    4.0 * t * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }

            // Exponential 1dB: fast start, slow end
            // y = (e^t - 1) / (e - 1)
            FadeCurve::Exp1 => (E.powf(t) - 1.0) / (E - 1.0),

            // Exponential 3dB: steeper exponential
            // y = (e^(t*3) - 1) / (e^3 - 1)
            FadeCurve::Exp3 => (E.powf(t * 3.0) - 1.0) / (E.powi(3) - 1.0),
        }
    }

    /// Evaluate curve for fade-out (inverted)
    ///
    /// For fade-out, we want the curve to go from 1.0 to 0.0
    #[inline]
    pub fn evaluate_fadeout(&self, t: f32) -> f32 {
        1.0 - self.evaluate(t)
    }

    /// Get curve value at specific frame during a fade
    ///
    /// # Arguments
    /// * `current_frame` - Current frame in the fade
    /// * `total_frames` - Total frames in the fade
    /// * `is_fadeout` - True for fade-out, false for fade-in
    #[inline]
    pub fn value_at_frame(&self, current_frame: u64, total_frames: u64, is_fadeout: bool) -> f32 {
        if total_frames == 0 {
            return if is_fadeout { 0.0 } else { 1.0 };
        }

        let t = (current_frame as f32) / (total_frames as f32);

        if is_fadeout {
            self.evaluate_fadeout(t)
        } else {
            self.evaluate(t)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EQUAL POWER CROSSFADE (Bonus)
// ═══════════════════════════════════════════════════════════════════════════════

/// Equal power crossfade calculation
///
/// For crossfading between two sources without volume dip.
#[inline]
pub fn equal_power_crossfade(t: f32) -> (f32, f32) {
    let t = t.clamp(0.0, 1.0);
    let angle = t * FRAC_PI_2;

    // gain_a decreases, gain_b increases
    // Sum of squares = 1.0 (constant power)
    let gain_a = angle.cos();
    let gain_b = angle.sin();

    (gain_a, gain_b)
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_curve_boundaries() {
        for curve in [
            FadeCurve::Linear,
            FadeCurve::Log3,
            FadeCurve::Sine,
            FadeCurve::Log1,
            FadeCurve::InvSCurve,
            FadeCurve::SCurve,
            FadeCurve::Exp1,
            FadeCurve::Exp3,
        ] {
            // Start should be ~0
            assert!((curve.evaluate(0.0) - 0.0).abs() < 0.001, "{:?} at 0.0", curve);

            // End should be ~1
            assert!((curve.evaluate(1.0) - 1.0).abs() < 0.001, "{:?} at 1.0", curve);

            // Middle should be between 0 and 1
            let mid = curve.evaluate(0.5);
            assert!(mid > 0.0 && mid < 1.0, "{:?} at 0.5 = {}", curve, mid);
        }
    }

    #[test]
    fn test_curve_monotonic() {
        for curve in [
            FadeCurve::Linear,
            FadeCurve::Log3,
            FadeCurve::Sine,
            FadeCurve::Log1,
            FadeCurve::InvSCurve,
            FadeCurve::SCurve,
            FadeCurve::Exp1,
            FadeCurve::Exp3,
        ] {
            let mut prev = 0.0;
            for i in 0..=100 {
                let t = i as f32 / 100.0;
                let val = curve.evaluate(t);
                assert!(val >= prev - 0.0001, "{:?}: {} < {} at t={}", curve, val, prev, t);
                prev = val;
            }
        }
    }

    #[test]
    fn test_equal_power() {
        // At t=0, gain_a=1, gain_b=0
        let (a, b) = equal_power_crossfade(0.0);
        assert!((a - 1.0).abs() < 0.001);
        assert!(b.abs() < 0.001);

        // At t=1, gain_a=0, gain_b=1
        let (a, b) = equal_power_crossfade(1.0);
        assert!(a.abs() < 0.001);
        assert!((b - 1.0).abs() < 0.001);

        // At t=0.5, both should be ~0.707 (sqrt(0.5))
        let (a, b) = equal_power_crossfade(0.5);
        assert!((a - 0.707).abs() < 0.01);
        assert!((b - 0.707).abs() < 0.01);

        // Power should be constant
        for i in 0..=100 {
            let t = i as f32 / 100.0;
            let (a, b) = equal_power_crossfade(t);
            let power = a * a + b * b;
            assert!((power - 1.0).abs() < 0.001, "Power at t={}: {}", t, power);
        }
    }

    #[test]
    fn test_fadeout() {
        let curve = FadeCurve::Linear;

        // Fadeout at t=0 should be 1.0
        assert!((curve.evaluate_fadeout(0.0) - 1.0).abs() < 0.001);

        // Fadeout at t=1 should be 0.0
        assert!((curve.evaluate_fadeout(1.0) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_from_index() {
        assert_eq!(FadeCurve::from_index(0), FadeCurve::Linear);
        assert_eq!(FadeCurve::from_index(5), FadeCurve::SCurve);
        assert_eq!(FadeCurve::from_index(255), FadeCurve::Linear); // Invalid → default
    }
}
