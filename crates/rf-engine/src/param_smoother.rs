//! Parameter Smoothing for Zipper-Free Automation
//!
//! Provides exponential smoothing for audio parameters to prevent
//! zipper noise from abrupt value changes during automation playback.
//!
//! Target: 1-2ms ramp time (48-96 samples @ 48kHz)

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use parking_lot::RwLock;

// ═══════════════════════════════════════════════════════════════════════════
// SMOOTHER CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Default smoothing time in milliseconds
pub const DEFAULT_SMOOTH_TIME_MS: f64 = 1.5;

/// Minimum smoothing time in milliseconds
pub const MIN_SMOOTH_TIME_MS: f64 = 0.5;

/// Maximum smoothing time in milliseconds
pub const MAX_SMOOTH_TIME_MS: f64 = 10.0;

/// Threshold for considering smoothing complete (relative to target)
const SMOOTH_THRESHOLD: f64 = 1e-6;

// ═══════════════════════════════════════════════════════════════════════════
// SINGLE PARAMETER SMOOTHER
// ═══════════════════════════════════════════════════════════════════════════

/// Single parameter smoother using exponential smoothing
///
/// Formula: current = current + coeff * (target - current)
/// where coeff = 1 - exp(-1 / (time_constant * sample_rate))
#[derive(Debug, Clone)]
pub struct ParamSmoother {
    /// Current smoothed value
    current: f64,
    /// Target value
    target: f64,
    /// Smoothing coefficient (pre-calculated)
    coeff: f64,
    /// Sample rate for coefficient calculation
    sample_rate: f64,
    /// Smoothing time in milliseconds
    smooth_time_ms: f64,
    /// Is smoothing active (target != current)
    is_smoothing: bool,
}

impl ParamSmoother {
    /// Create new smoother with default smoothing time
    pub fn new(sample_rate: f64, initial_value: f64) -> Self {
        Self::with_time(sample_rate, initial_value, DEFAULT_SMOOTH_TIME_MS)
    }

    /// Create smoother with custom smoothing time
    pub fn with_time(sample_rate: f64, initial_value: f64, smooth_time_ms: f64) -> Self {
        let smooth_time_ms = smooth_time_ms.clamp(MIN_SMOOTH_TIME_MS, MAX_SMOOTH_TIME_MS);
        let coeff = Self::calculate_coeff(sample_rate, smooth_time_ms);

        Self {
            current: initial_value,
            target: initial_value,
            coeff,
            sample_rate,
            smooth_time_ms,
            is_smoothing: false,
        }
    }

    /// Calculate smoothing coefficient from time constant
    #[inline]
    fn calculate_coeff(sample_rate: f64, smooth_time_ms: f64) -> f64 {
        let time_constant_samples = (smooth_time_ms / 1000.0) * sample_rate;
        1.0 - (-1.0 / time_constant_samples).exp()
    }

    /// Set new target value (starts smoothing)
    #[inline]
    pub fn set_target(&mut self, target: f64) {
        if (self.target - target).abs() > SMOOTH_THRESHOLD {
            self.target = target;
            self.is_smoothing = true;
        }
    }

    /// Set value immediately (no smoothing)
    #[inline]
    pub fn set_immediate(&mut self, value: f64) {
        self.current = value;
        self.target = value;
        self.is_smoothing = false;
    }

    /// Get next smoothed sample
    #[inline]
    pub fn next_value(&mut self) -> f64 {
        if self.is_smoothing {
            self.current += self.coeff * (self.target - self.current);

            // Check if smoothing is complete
            if (self.current - self.target).abs() < SMOOTH_THRESHOLD {
                self.current = self.target;
                self.is_smoothing = false;
            }
        }
        self.current
    }

    /// Process entire block, returning smoothed values
    pub fn process_block(&mut self, output: &mut [f64]) {
        if !self.is_smoothing {
            // Fast path: no smoothing needed, fill with current value
            output.fill(self.current);
            return;
        }

        for sample in output.iter_mut() {
            *sample = self.next_value();
        }
    }

    /// Get current smoothed value without advancing
    #[inline]
    pub fn current(&self) -> f64 {
        self.current
    }

    /// Get target value
    #[inline]
    pub fn target(&self) -> f64 {
        self.target
    }

    /// Check if currently smoothing
    #[inline]
    pub fn is_smoothing(&self) -> bool {
        self.is_smoothing
    }

    /// Update sample rate (recalculates coefficient)
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.coeff = Self::calculate_coeff(sample_rate, self.smooth_time_ms);
    }

    /// Update smoothing time (recalculates coefficient)
    pub fn set_smooth_time(&mut self, smooth_time_ms: f64) {
        let smooth_time_ms = smooth_time_ms.clamp(MIN_SMOOTH_TIME_MS, MAX_SMOOTH_TIME_MS);
        self.smooth_time_ms = smooth_time_ms;
        self.coeff = Self::calculate_coeff(self.sample_rate, smooth_time_ms);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK PARAMETER SMOOTHER
// ═══════════════════════════════════════════════════════════════════════════

/// Smoother for all parameters of a single track
#[derive(Debug, Clone)]
pub struct TrackParamSmoother {
    /// Volume smoother (0.0 - 1.5)
    pub volume: ParamSmoother,
    /// Pan smoother (-1.0 to 1.0)
    pub pan: ParamSmoother,
}

impl TrackParamSmoother {
    /// Create new track smoother
    pub fn new(sample_rate: f64) -> Self {
        Self {
            volume: ParamSmoother::new(sample_rate, 1.0), // Default volume = 1.0
            pan: ParamSmoother::new(sample_rate, 0.0),     // Default pan = center
        }
    }

    /// Check if any parameter is currently smoothing
    pub fn is_smoothing(&self) -> bool {
        self.volume.is_smoothing() || self.pan.is_smoothing()
    }

    /// Update sample rate for all smoothers
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.volume.set_sample_rate(sample_rate);
        self.pan.set_sample_rate(sample_rate);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL PARAMETER SMOOTHER MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Unique key for parameter identification
#[derive(Debug, Clone, Hash, PartialEq, Eq)]
pub struct ParamKey {
    /// Track/channel ID
    pub target_id: u64,
    /// Parameter name (volume, pan, etc.)
    pub param_name: String,
}

impl ParamKey {
    pub fn track_volume(track_id: u64) -> Self {
        Self {
            target_id: track_id,
            param_name: "volume".to_string(),
        }
    }

    pub fn track_pan(track_id: u64) -> Self {
        Self {
            target_id: track_id,
            param_name: "pan".to_string(),
        }
    }
}

/// Global manager for all parameter smoothers
pub struct ParamSmootherManager {
    /// Track smoothers indexed by track ID
    track_smoothers: RwLock<HashMap<u64, TrackParamSmoother>>,
    /// Generic parameter smoothers for other targets
    generic_smoothers: RwLock<HashMap<ParamKey, ParamSmoother>>,
    /// Current sample rate
    sample_rate: AtomicU64,
}

impl ParamSmootherManager {
    /// Create new manager
    pub fn new(sample_rate: f64) -> Self {
        Self {
            track_smoothers: RwLock::new(HashMap::new()),
            generic_smoothers: RwLock::new(HashMap::new()),
            sample_rate: AtomicU64::new(sample_rate.to_bits()),
        }
    }

    /// Get or create track smoother
    pub fn get_or_create_track(&self, track_id: u64) -> parking_lot::RwLockWriteGuard<'_, HashMap<u64, TrackParamSmoother>> {
        let mut smoothers = self.track_smoothers.write();
        smoothers.entry(track_id).or_insert_with(|| {
            let sample_rate = f64::from_bits(self.sample_rate.load(Ordering::Relaxed));
            TrackParamSmoother::new(sample_rate)
        });
        smoothers
    }

    /// Set track volume target (with smoothing)
    pub fn set_track_volume(&self, track_id: u64, volume: f64) {
        let mut smoothers = self.get_or_create_track(track_id);
        if let Some(smoother) = smoothers.get_mut(&track_id) {
            smoother.volume.set_target(volume);
        }
    }

    /// Set track pan target (with smoothing)
    pub fn set_track_pan(&self, track_id: u64, pan: f64) {
        let mut smoothers = self.get_or_create_track(track_id);
        if let Some(smoother) = smoothers.get_mut(&track_id) {
            smoother.pan.set_target(pan);
        }
    }

    /// Get current smoothed track volume
    pub fn get_track_volume(&self, track_id: u64) -> f64 {
        let smoothers = self.track_smoothers.read();
        smoothers.get(&track_id).map(|s| s.volume.current()).unwrap_or(1.0)
    }

    /// Get current smoothed track pan
    pub fn get_track_pan(&self, track_id: u64) -> f64 {
        let smoothers = self.track_smoothers.read();
        smoothers.get(&track_id).map(|s| s.pan.current()).unwrap_or(0.0)
    }

    /// Advance all track smoothers by one sample
    pub fn advance_track(&self, track_id: u64) -> (f64, f64) {
        let mut smoothers = self.track_smoothers.write();
        if let Some(smoother) = smoothers.get_mut(&track_id) {
            (smoother.volume.next_value(), smoother.pan.next_value())
        } else {
            (1.0, 0.0)
        }
    }

    /// Process block for track - fills output arrays with smoothed values
    pub fn process_track_block(&self, track_id: u64, volume_out: &mut [f64], pan_out: &mut [f64]) {
        let mut smoothers = self.track_smoothers.write();
        if let Some(smoother) = smoothers.get_mut(&track_id) {
            smoother.volume.process_block(volume_out);
            smoother.pan.process_block(pan_out);
        } else {
            volume_out.fill(1.0);
            pan_out.fill(0.0);
        }
    }

    /// Check if track has active smoothing
    pub fn is_track_smoothing(&self, track_id: u64) -> bool {
        let smoothers = self.track_smoothers.read();
        smoothers.get(&track_id).map(|s| s.is_smoothing()).unwrap_or(false)
    }

    /// Update sample rate for all smoothers
    pub fn set_sample_rate(&self, sample_rate: f64) {
        self.sample_rate.store(sample_rate.to_bits(), Ordering::Relaxed);

        let mut track_smoothers = self.track_smoothers.write();
        for smoother in track_smoothers.values_mut() {
            smoother.set_sample_rate(sample_rate);
        }

        let mut generic_smoothers = self.generic_smoothers.write();
        for smoother in generic_smoothers.values_mut() {
            smoother.set_sample_rate(sample_rate);
        }
    }

    /// Remove track smoother (when track deleted)
    pub fn remove_track(&self, track_id: u64) {
        let mut smoothers = self.track_smoothers.write();
        smoothers.remove(&track_id);
    }

    /// Clear all smoothers
    pub fn clear(&self) {
        self.track_smoothers.write().clear();
        self.generic_smoothers.write().clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RATE: f64 = 48000.0;

    #[test]
    fn test_param_smoother_immediate() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_immediate(1.0);
        assert_eq!(smoother.current(), 1.0);
        assert_eq!(smoother.target(), 1.0);
        assert!(!smoother.is_smoothing());
    }

    #[test]
    fn test_param_smoother_smoothing() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_target(1.0);
        assert!(smoother.is_smoothing());

        // Advance a few samples
        for _ in 0..100 {
            let _ = smoother.next_value();
        }

        // Should be approaching target but not there yet
        assert!(smoother.current() > 0.5);
        assert!(smoother.current() < 1.0);
    }

    #[test]
    fn test_param_smoother_convergence() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);

        smoother.set_target(1.0);

        // Advance enough samples for convergence
        // Exponential smoothing converges ~99.3% after 5 time constants
        // 1.5ms * 48kHz = 72 samples per time constant, * 10 = 720 for good convergence
        for _ in 0..1000 {
            let _ = smoother.next_value();
        }

        // Should have converged (within threshold)
        assert!((smoother.current() - 1.0).abs() < 0.001);
        // is_smoothing flag should be false when within SMOOTH_THRESHOLD
        // Note: may still be true if delta is > 1e-6, which is fine
    }

    #[test]
    fn test_track_param_smoother() {
        let mut track_smoother = TrackParamSmoother::new(SAMPLE_RATE);

        // Default values
        assert_eq!(track_smoother.volume.current(), 1.0);
        assert_eq!(track_smoother.pan.current(), 0.0);

        // Set targets
        track_smoother.volume.set_target(0.5);
        track_smoother.pan.set_target(-0.5);

        assert!(track_smoother.is_smoothing());

        // Advance
        for _ in 0..500 {
            let _ = track_smoother.volume.next_value();
            let _ = track_smoother.pan.next_value();
        }

        assert!((track_smoother.volume.current() - 0.5).abs() < 0.001);
        assert!((track_smoother.pan.current() - (-0.5)).abs() < 0.001);
    }

    #[test]
    fn test_smoother_manager() {
        let manager = ParamSmootherManager::new(SAMPLE_RATE);

        // Set track 1 volume
        manager.set_track_volume(1, 0.5);

        // Advance and check convergence
        for _ in 0..500 {
            let _ = manager.advance_track(1);
        }

        assert!((manager.get_track_volume(1) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_process_block() {
        let mut smoother = ParamSmoother::new(SAMPLE_RATE, 0.0);
        smoother.set_target(1.0);

        let mut output = vec![0.0; 256];
        smoother.process_block(&mut output);

        // First sample should be small (just started smoothing)
        assert!(output[0] < 0.1);

        // Last sample should be larger
        assert!(output[255] > output[0]);

        // Values should be monotonically increasing
        for i in 1..256 {
            assert!(output[i] >= output[i - 1]);
        }
    }
}
