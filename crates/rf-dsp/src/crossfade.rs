//! Crossfade Processor — smooth audio transitions between two sources
//!
//! Provides sample-accurate crossfading with multiple curve types for
//! tempo state transitions (dual-voice approach).
//!
//! # Audio Thread Safety
//! All processing methods are allocation-free and lock-free.
//! Pre-computed fade tables ensure zero runtime math beyond table lookup + lerp.
//!
//! # Supported Curves
//! - Linear: constant-amplitude crossfade
//! - EqualPower: constant-power (-3dB at midpoint), no volume dip
//! - SCurve: smooth start/end, perceptually natural

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FadeCurve {
    /// Linear crossfade (constant amplitude)
    Linear,
    /// Equal power crossfade (constant power, -3dB at midpoint)
    EqualPower,
    /// S-curve (smoothstep, perceptually smooth)
    SCurve,
}

/// State of the crossfade processor
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CrossfadeState {
    /// No crossfade active — only source A plays
    Idle,
    /// Crossfade in progress — both sources play
    Active,
    /// Crossfade complete — only source B plays
    Complete,
}

/// Stereo sample pair
#[derive(Debug, Clone, Copy, Default)]
pub struct StereoSample {
    pub left: f64,
    pub right: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CROSSFADE PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Sample-accurate crossfade between two audio sources
///
/// # Usage
/// ```ignore
/// let mut xfade = CrossfadeProcessor::new(FadeCurve::EqualPower);
///
/// // Start a 2-second crossfade at 44100 Hz
/// xfade.start(88200);
///
/// // In audio callback:
/// for i in 0..block_size {
///     let (gain_a, gain_b) = xfade.next_gains();
///     output[i] = source_a[i] * gain_a + source_b[i] * gain_b;
/// }
/// ```
pub struct CrossfadeProcessor {
    /// Fade curve type
    curve: FadeCurve,
    /// Current state
    state: CrossfadeState,
    /// Total crossfade duration in samples
    duration_samples: u64,
    /// Current sample position in crossfade
    position: u64,
    /// Pre-computed fade table (source A gain values)
    /// Source B gain is derived from curve type
    fade_table: Vec<f64>,
    /// Table size for lookup
    table_size: usize,
}

/// Maximum table size — trades memory for interpolation accuracy
const FADE_TABLE_SIZE: usize = 4096;

impl CrossfadeProcessor {
    /// Create a new crossfade processor
    pub fn new(curve: FadeCurve) -> Self {
        let table = build_fade_table(curve, FADE_TABLE_SIZE);
        Self {
            curve,
            state: CrossfadeState::Idle,
            duration_samples: 0,
            position: 0,
            fade_table: table,
            table_size: FADE_TABLE_SIZE,
        }
    }

    /// Change the fade curve (rebuilds lookup table)
    pub fn set_curve(&mut self, curve: FadeCurve) {
        if self.curve != curve {
            self.curve = curve;
            self.fade_table = build_fade_table(curve, FADE_TABLE_SIZE);
        }
    }

    /// Start a crossfade with the given duration in samples
    ///
    /// Source A fades out, Source B fades in.
    pub fn start(&mut self, duration_samples: u64) {
        if duration_samples == 0 {
            self.state = CrossfadeState::Complete;
            self.position = 0;
            self.duration_samples = 0;
            return;
        }
        self.duration_samples = duration_samples;
        self.position = 0;
        self.state = CrossfadeState::Active;
    }

    /// Get current crossfade state
    pub fn state(&self) -> CrossfadeState {
        self.state
    }

    /// Get the next gain pair (gain_a, gain_b) and advance position
    ///
    /// # Audio Thread Safe
    /// Only table lookup + linear interpolation. No allocation.
    ///
    /// # Returns
    /// `(gain_a, gain_b)` where:
    /// - `gain_a` is the fade-out gain for source A
    /// - `gain_b` is the fade-in gain for source B
    #[inline]
    pub fn next_gains(&mut self) -> (f64, f64) {
        match self.state {
            CrossfadeState::Idle => (1.0, 0.0),
            CrossfadeState::Complete => (0.0, 1.0),
            CrossfadeState::Active => {
                let t = self.position as f64 / self.duration_samples as f64;
                let gain_a = table_lookup(&self.fade_table, self.table_size, t);
                let gain_b = complementary_gain(self.curve, gain_a, t);

                self.position += 1;
                if self.position >= self.duration_samples {
                    self.state = CrossfadeState::Complete;
                }

                (gain_a, gain_b)
            }
        }
    }

    /// Process a block of stereo samples from two sources
    ///
    /// # Audio Thread Safe
    /// Writes directly into output buffer. No allocations.
    ///
    /// # Arguments
    /// * `source_a` - Fade-out source (left, right interleaved or separate)
    /// * `source_b` - Fade-in source
    /// * `output_left` - Output left channel
    /// * `output_right` - Output right channel
    pub fn process_block(
        &mut self,
        source_a_left: &[f64],
        source_a_right: &[f64],
        source_b_left: &[f64],
        source_b_right: &[f64],
        output_left: &mut [f64],
        output_right: &mut [f64],
    ) {
        let len = source_a_left.len()
            .min(source_a_right.len())
            .min(source_b_left.len())
            .min(source_b_right.len())
            .min(output_left.len())
            .min(output_right.len());

        for i in 0..len {
            let (ga, gb) = self.next_gains();
            output_left[i] = source_a_left[i] * ga + source_b_left[i] * gb;
            output_right[i] = source_a_right[i] * ga + source_b_right[i] * gb;
        }
    }

    /// Process mono block from two sources
    pub fn process_block_mono(
        &mut self,
        source_a: &[f64],
        source_b: &[f64],
        output: &mut [f64],
    ) {
        let len = source_a.len().min(source_b.len()).min(output.len());

        for i in 0..len {
            let (ga, gb) = self.next_gains();
            output[i] = source_a[i] * ga + source_b[i] * gb;
        }
    }

    /// Get current progress (0.0 = start, 1.0 = complete)
    pub fn progress(&self) -> f64 {
        match self.state {
            CrossfadeState::Idle => 0.0,
            CrossfadeState::Complete => 1.0,
            CrossfadeState::Active => {
                if self.duration_samples == 0 { 1.0 }
                else { self.position as f64 / self.duration_samples as f64 }
            }
        }
    }

    /// Reset to idle state
    pub fn reset(&mut self) {
        self.state = CrossfadeState::Idle;
        self.position = 0;
        self.duration_samples = 0;
    }

    /// Is the crossfade currently active?
    pub fn is_active(&self) -> bool {
        self.state == CrossfadeState::Active
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FADE TABLE CONSTRUCTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Build a pre-computed fade table for source A (fade-out) gain values
///
/// Table maps t (0.0 → 1.0) to gain_a (1.0 → 0.0)
fn build_fade_table(curve: FadeCurve, size: usize) -> Vec<f64> {
    let mut table = Vec::with_capacity(size);
    for i in 0..size {
        let t = i as f64 / (size - 1) as f64;
        let gain_a = match curve {
            FadeCurve::Linear => 1.0 - t,
            FadeCurve::EqualPower => (t * PI * 0.5).cos(),
            FadeCurve::SCurve => {
                let s = t * t * (3.0 - 2.0 * t); // smoothstep
                1.0 - s
            }
        };
        table.push(gain_a);
    }
    table
}

/// Get the complementary gain for source B based on curve type
///
/// For equal power: gain_b = sin(t * pi/2) (NOT 1 - gain_a)
/// For linear/S-curve: gain_b = 1 - gain_a (constant amplitude)
#[inline]
fn complementary_gain(curve: FadeCurve, gain_a: f64, t: f64) -> f64 {
    match curve {
        FadeCurve::EqualPower => (t * PI * 0.5).sin(),
        _ => 1.0 - gain_a,
    }
}

/// Lookup value from fade table with linear interpolation
#[inline]
fn table_lookup(table: &[f64], table_size: usize, t: f64) -> f64 {
    let t = t.clamp(0.0, 1.0);
    let pos = t * (table_size - 1) as f64;
    let idx = pos as usize;
    let frac = pos - idx as f64;

    if idx >= table_size - 1 {
        table[table_size - 1]
    } else {
        table[idx] + frac * (table[idx + 1] - table[idx])
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_idle_state() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        let (ga, gb) = xfade.next_gains();
        assert!((ga - 1.0).abs() < 0.001);
        assert!(gb.abs() < 0.001);
    }

    #[test]
    fn test_linear_crossfade_endpoints() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(1000);

        // First sample: gain_a ~1.0, gain_b ~0.0
        let (ga, gb) = xfade.next_gains();
        assert!((ga - 1.0).abs() < 0.01);
        assert!(gb.abs() < 0.01);

        // Advance to end
        for _ in 1..999 {
            xfade.next_gains();
        }

        // Last sample: gain_a ~0.0, gain_b ~1.0
        let (ga, gb) = xfade.next_gains();
        assert!(ga.abs() < 0.01);
        assert!((gb - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_linear_midpoint() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(1000);

        // Advance to midpoint
        for _ in 0..500 {
            xfade.next_gains();
        }

        let (ga, gb) = xfade.next_gains();
        assert!((ga - 0.5).abs() < 0.02, "Linear midpoint gain_a should be ~0.5, got {}", ga);
        assert!((gb - 0.5).abs() < 0.02, "Linear midpoint gain_b should be ~0.5, got {}", gb);
    }

    #[test]
    fn test_equal_power_no_dip() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::EqualPower);
        xfade.start(1000);

        // Check that total power (ga^2 + gb^2) stays approximately 1.0
        let mut min_power = f64::MAX;
        for _ in 0..1000 {
            let (ga, gb) = xfade.next_gains();
            let power = ga * ga + gb * gb;
            if power < min_power {
                min_power = power;
            }
        }

        assert!((min_power - 1.0).abs() < 0.01,
            "Equal power should maintain ~1.0 total power, min was {}", min_power);
    }

    #[test]
    fn test_equal_power_midpoint() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::EqualPower);
        xfade.start(1000);

        for _ in 0..500 {
            xfade.next_gains();
        }

        let (ga, gb) = xfade.next_gains();
        // At midpoint, both should be ~0.707 (-3dB)
        assert!((ga - 0.707).abs() < 0.02, "EP midpoint gain_a ~0.707, got {}", ga);
        assert!((gb - 0.707).abs() < 0.02, "EP midpoint gain_b ~0.707, got {}", gb);
    }

    #[test]
    fn test_scurve_smooth() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::SCurve);
        xfade.start(1000);

        // S-curve midpoint should be ~0.5 (smoothstep(0.5) = 0.5)
        for _ in 0..500 {
            xfade.next_gains();
        }

        let (ga, gb) = xfade.next_gains();
        assert!((ga - 0.5).abs() < 0.02, "S-curve midpoint gain_a ~0.5, got {}", ga);
        assert!((gb - 0.5).abs() < 0.02, "S-curve midpoint gain_b ~0.5, got {}", gb);
    }

    #[test]
    fn test_crossfade_completes() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(100);

        for _ in 0..100 {
            xfade.next_gains();
        }

        assert_eq!(xfade.state(), CrossfadeState::Complete);
        let (ga, gb) = xfade.next_gains();
        assert!(ga.abs() < 0.001);
        assert!((gb - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_zero_duration() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(0);

        assert_eq!(xfade.state(), CrossfadeState::Complete);
    }

    #[test]
    fn test_process_block_mono() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(4);

        let src_a = [1.0, 1.0, 1.0, 1.0];
        let src_b = [0.0, 0.0, 0.0, 0.0];
        let mut out = [0.0; 4];

        xfade.process_block_mono(&src_a, &src_b, &mut out);

        // Linear fade: output should decrease from ~1.0 to ~0.0
        assert!(out[0] > out[3]);
        assert!(out[0] > 0.5);
    }

    #[test]
    fn test_reset() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        xfade.start(100);
        for _ in 0..50 { xfade.next_gains(); }

        xfade.reset();

        assert_eq!(xfade.state(), CrossfadeState::Idle);
        let (ga, gb) = xfade.next_gains();
        assert!((ga - 1.0).abs() < 0.001);
        assert!(gb.abs() < 0.001);
    }

    #[test]
    fn test_progress() {
        let mut xfade = CrossfadeProcessor::new(FadeCurve::Linear);
        assert!((xfade.progress() - 0.0).abs() < 0.001);

        xfade.start(100);
        for _ in 0..50 { xfade.next_gains(); }
        assert!((xfade.progress() - 0.5).abs() < 0.02);

        for _ in 0..50 { xfade.next_gains(); }
        assert!((xfade.progress() - 1.0).abs() < 0.001);
    }
}
