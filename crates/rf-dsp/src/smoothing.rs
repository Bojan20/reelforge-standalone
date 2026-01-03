//! Lock-Free Parameter Smoothing
//!
//! Provides click-free parameter changes with:
//! - Atomic parameter updates (UI → Audio thread)
//! - Multiple smoothing algorithms
//! - Zero allocation in audio thread
//! - Configurable smoothing time
//!
//! # Design
//! Uses atomic operations for lock-free communication.
//! Smoothing happens in audio thread using pre-computed coefficients.

use std::sync::atomic::{AtomicU64, AtomicBool, Ordering};
use rf_core::Sample;

// ============ Smoothing Algorithms ============

/// Smoothing algorithm type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SmoothingType {
    /// Linear ramp (constant rate)
    #[default]
    Linear,
    /// Exponential decay (RC filter style)
    Exponential,
    /// Logarithmic (fast start, slow end)
    Logarithmic,
    /// S-curve (slow start and end)
    SCurve,
    /// No smoothing (instant change)
    None,
}

// ============ Smoothed Parameter ============

/// Lock-free smoothed parameter for audio processing
#[derive(Debug)]
pub struct SmoothedParam {
    /// Target value (set from UI thread)
    target: AtomicU64,
    /// Current smoothed value
    current: f64,
    /// Smoothing coefficient for exponential
    coeff: f64,
    /// Smoothing type
    smoothing_type: SmoothingType,
    /// Smoothing time in samples
    smoothing_samples: f64,
    /// Step size for linear smoothing
    linear_step: f64,
    /// Remaining samples for linear smoothing
    linear_remaining: i32,
    /// Flag indicating value has changed
    dirty: AtomicBool,
    /// Sample rate for time calculations
    sample_rate: f64,
    /// Minimum value
    min_value: f64,
    /// Maximum value
    max_value: f64,
}

impl SmoothedParam {
    /// Create new smoothed parameter
    pub fn new(
        initial_value: f64,
        smoothing_time_ms: f64,
        sample_rate: f64,
        smoothing_type: SmoothingType,
    ) -> Self {
        let smoothing_samples = (smoothing_time_ms / 1000.0) * sample_rate;
        let coeff = Self::calculate_coeff(smoothing_samples);

        Self {
            target: AtomicU64::new(initial_value.to_bits()),
            current: initial_value,
            coeff,
            smoothing_type,
            smoothing_samples,
            linear_step: 0.0,
            linear_remaining: 0,
            dirty: AtomicBool::new(false),
            sample_rate,
            min_value: f64::NEG_INFINITY,
            max_value: f64::INFINITY,
        }
    }

    /// Create with value range
    pub fn with_range(
        initial_value: f64,
        smoothing_time_ms: f64,
        sample_rate: f64,
        smoothing_type: SmoothingType,
        min: f64,
        max: f64,
    ) -> Self {
        let mut param = Self::new(initial_value, smoothing_time_ms, sample_rate, smoothing_type);
        param.min_value = min;
        param.max_value = max;
        param
    }

    /// Calculate exponential smoothing coefficient
    fn calculate_coeff(samples: f64) -> f64 {
        if samples <= 0.0 {
            1.0
        } else {
            // Time constant: reach ~63% in smoothing_samples
            1.0 - (-1.0 / samples).exp()
        }
    }

    /// Set smoothing time in milliseconds
    pub fn set_smoothing_time(&mut self, time_ms: f64) {
        self.smoothing_samples = (time_ms / 1000.0) * self.sample_rate;
        self.coeff = Self::calculate_coeff(self.smoothing_samples);
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        let time_ms = (self.smoothing_samples / self.sample_rate) * 1000.0;
        self.set_smoothing_time(time_ms);
    }

    /// Set smoothing type
    pub fn set_smoothing_type(&mut self, smoothing_type: SmoothingType) {
        self.smoothing_type = smoothing_type;
    }

    /// Set target value (thread-safe, call from UI)
    #[inline]
    pub fn set_target(&self, value: f64) {
        let clamped = value.clamp(self.min_value, self.max_value);
        self.target.store(clamped.to_bits(), Ordering::Relaxed);
        self.dirty.store(true, Ordering::Relaxed);
    }

    /// Get target value
    #[inline]
    pub fn target(&self) -> f64 {
        f64::from_bits(self.target.load(Ordering::Relaxed))
    }

    /// Get current smoothed value
    #[inline]
    pub fn current(&self) -> f64 {
        self.current
    }

    /// Set current value immediately (for initialization)
    pub fn set_immediate(&mut self, value: f64) {
        let clamped = value.clamp(self.min_value, self.max_value);
        self.current = clamped;
        self.target.store(clamped.to_bits(), Ordering::Relaxed);
        self.linear_remaining = 0;
        self.dirty.store(false, Ordering::Relaxed);
    }

    /// Check if smoothing is active
    #[inline]
    pub fn is_smoothing(&self) -> bool {
        match self.smoothing_type {
            SmoothingType::None => false,
            SmoothingType::Linear => self.linear_remaining > 0,
            _ => (self.current - self.target()).abs() > 1e-10,
        }
    }

    /// Process one sample of smoothing
    #[inline]
    pub fn next(&mut self) -> f64 {
        let target = self.target();

        match self.smoothing_type {
            SmoothingType::None => {
                self.current = target;
            }
            SmoothingType::Exponential => {
                self.current += self.coeff * (target - self.current);
            }
            SmoothingType::Linear => {
                // Check if target changed
                if self.dirty.swap(false, Ordering::Relaxed) {
                    // Recalculate linear ramp
                    let diff = target - self.current;
                    self.linear_remaining = self.smoothing_samples as i32;
                    if self.linear_remaining > 0 {
                        self.linear_step = diff / self.linear_remaining as f64;
                    } else {
                        self.current = target;
                        self.linear_step = 0.0;
                    }
                }

                if self.linear_remaining > 0 {
                    self.current += self.linear_step;
                    self.linear_remaining -= 1;
                } else {
                    self.current = target;
                }
            }
            SmoothingType::Logarithmic => {
                // Fast start, slow end
                let t = self.coeff * 2.0;
                self.current += t * (target - self.current).signum()
                    * (target - self.current).abs().sqrt().copysign(target - self.current);
            }
            SmoothingType::SCurve => {
                // Use exponential with variable speed
                let diff = (target - self.current).abs();
                let adaptive_coeff = self.coeff * (1.0 + diff.min(1.0));
                self.current += adaptive_coeff * (target - self.current);
            }
        }

        self.current
    }

    /// Get next value without state change (peek)
    #[inline]
    pub fn peek_next(&self) -> f64 {
        let target = self.target();

        match self.smoothing_type {
            SmoothingType::None => target,
            SmoothingType::Exponential => {
                self.current + self.coeff * (target - self.current)
            }
            SmoothingType::Linear => {
                if self.linear_remaining > 0 {
                    self.current + self.linear_step
                } else {
                    target
                }
            }
            _ => self.current + self.coeff * (target - self.current),
        }
    }

    /// Fill buffer with smoothed values
    pub fn fill_buffer(&mut self, buffer: &mut [Sample]) {
        for sample in buffer.iter_mut() {
            *sample = self.next();
        }
    }

    /// Process block, applying smoothed gain to audio
    pub fn apply_gain(&mut self, buffer: &mut [Sample]) {
        for sample in buffer.iter_mut() {
            *sample *= self.next();
        }
    }

    /// Reset to target value instantly
    pub fn reset(&mut self) {
        let target = self.target();
        self.current = target;
        self.linear_remaining = 0;
        self.dirty.store(false, Ordering::Relaxed);
    }
}

// ============ Smoothed Stereo Param ============

/// Smoothed parameter for stereo (e.g., pan)
#[derive(Debug)]
pub struct SmoothedStereoParam {
    /// Left channel gain
    pub left: SmoothedParam,
    /// Right channel gain
    pub right: SmoothedParam,
}

impl SmoothedStereoParam {
    /// Create from pan value (-1 to 1)
    pub fn from_pan(
        pan: f64,
        smoothing_time_ms: f64,
        sample_rate: f64,
        smoothing_type: SmoothingType,
    ) -> Self {
        let (left_gain, right_gain) = Self::pan_to_gains(pan);
        Self {
            left: SmoothedParam::new(left_gain, smoothing_time_ms, sample_rate, smoothing_type),
            right: SmoothedParam::new(right_gain, smoothing_time_ms, sample_rate, smoothing_type),
        }
    }

    /// Set pan value (-1 = full left, 0 = center, 1 = full right)
    pub fn set_pan(&self, pan: f64) {
        let (left_gain, right_gain) = Self::pan_to_gains(pan);
        self.left.set_target(left_gain);
        self.right.set_target(right_gain);
    }

    /// Convert pan to left/right gains (constant power)
    fn pan_to_gains(pan: f64) -> (f64, f64) {
        let pan = pan.clamp(-1.0, 1.0);
        // Constant power panning
        let angle = (pan + 1.0) * 0.25 * std::f64::consts::PI;
        (angle.cos(), angle.sin())
    }

    /// Apply smoothed pan to stereo buffer
    pub fn apply(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            *l *= self.left.next();
            *r *= self.right.next();
        }
    }

    /// Reset to current targets
    pub fn reset(&mut self) {
        self.left.reset();
        self.right.reset();
    }
}

// ============ Parameter Bank ============

/// Collection of smoothed parameters for a processor
#[derive(Debug)]
pub struct ParameterBank {
    params: Vec<SmoothedParam>,
    sample_rate: f64,
    default_smoothing_ms: f64,
    default_smoothing_type: SmoothingType,
}

impl ParameterBank {
    /// Create new parameter bank
    pub fn new(sample_rate: f64, default_smoothing_ms: f64, default_smoothing_type: SmoothingType) -> Self {
        Self {
            params: Vec::new(),
            sample_rate,
            default_smoothing_ms,
            default_smoothing_type,
        }
    }

    /// Add a parameter
    pub fn add(&mut self, initial_value: f64) -> usize {
        let index = self.params.len();
        self.params.push(SmoothedParam::new(
            initial_value,
            self.default_smoothing_ms,
            self.sample_rate,
            self.default_smoothing_type,
        ));
        index
    }

    /// Add a parameter with range
    pub fn add_with_range(&mut self, initial_value: f64, min: f64, max: f64) -> usize {
        let index = self.params.len();
        self.params.push(SmoothedParam::with_range(
            initial_value,
            self.default_smoothing_ms,
            self.sample_rate,
            self.default_smoothing_type,
            min,
            max,
        ));
        index
    }

    /// Get parameter by index
    pub fn get(&self, index: usize) -> Option<&SmoothedParam> {
        self.params.get(index)
    }

    /// Get mutable parameter by index
    pub fn get_mut(&mut self, index: usize) -> Option<&mut SmoothedParam> {
        self.params.get_mut(index)
    }

    /// Set target value for parameter
    pub fn set_target(&self, index: usize, value: f64) {
        if let Some(param) = self.params.get(index) {
            param.set_target(value);
        }
    }

    /// Get current value for parameter
    pub fn current(&self, index: usize) -> f64 {
        self.params.get(index).map(|p| p.current()).unwrap_or(0.0)
    }

    /// Process one sample for all parameters
    pub fn next_all(&mut self) -> Vec<f64> {
        self.params.iter_mut().map(|p| p.next()).collect()
    }

    /// Set sample rate for all parameters
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for param in &mut self.params {
            param.set_sample_rate(sample_rate);
        }
    }

    /// Reset all parameters to targets
    pub fn reset_all(&mut self) {
        for param in &mut self.params {
            param.reset();
        }
    }

    /// Number of parameters
    pub fn len(&self) -> usize {
        self.params.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.params.is_empty()
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exponential_smoothing() {
        let mut param = SmoothedParam::new(0.0, 10.0, 48000.0, SmoothingType::Exponential);
        param.set_target(1.0);

        // After many samples, should approach target
        for _ in 0..10000 {
            param.next();
        }

        assert!((param.current() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_linear_smoothing() {
        let mut param = SmoothedParam::new(0.0, 10.0, 1000.0, SmoothingType::Linear);
        // 10ms at 1000Hz = 10 samples
        param.set_target(1.0);

        // Should reach target in exactly smoothing_samples
        for _ in 0..10 {
            param.next();
        }

        assert!((param.current() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_no_smoothing() {
        let mut param = SmoothedParam::new(0.0, 10.0, 48000.0, SmoothingType::None);
        param.set_target(1.0);

        let value = param.next();
        assert!((value - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_immediate_set() {
        let mut param = SmoothedParam::new(0.0, 10.0, 48000.0, SmoothingType::Exponential);
        param.set_immediate(0.5);

        assert!((param.current() - 0.5).abs() < 1e-10);
        assert!((param.target() - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_value_clamping() {
        let param = SmoothedParam::with_range(
            0.5, 10.0, 48000.0, SmoothingType::Exponential, 0.0, 1.0
        );

        param.set_target(2.0);
        assert!((param.target() - 1.0).abs() < 1e-10);

        param.set_target(-1.0);
        assert!((param.target() - 0.0).abs() < 1e-10);
    }

    #[test]
    fn test_stereo_pan() {
        let mut param = SmoothedStereoParam::from_pan(
            0.0, 10.0, 48000.0, SmoothingType::Exponential
        );

        // Center pan should have equal gains
        param.set_pan(0.0);
        param.left.reset();
        param.right.reset();

        let left = param.left.current();
        let right = param.right.current();
        assert!((left - right).abs() < 0.01);

        // Full left
        param.set_pan(-1.0);
        param.left.reset();
        param.right.reset();
        assert!((param.left.current() - 1.0).abs() < 0.1);
        assert!(param.right.current() < 0.1);
    }

    #[test]
    fn test_parameter_bank() {
        let mut bank = ParameterBank::new(48000.0, 10.0, SmoothingType::Exponential);

        let idx1 = bank.add(0.0);
        let idx2 = bank.add_with_range(0.5, 0.0, 1.0);

        bank.set_target(idx1, 1.0);
        bank.set_target(idx2, 0.75);

        // Process many samples
        for _ in 0..10000 {
            bank.next_all();
        }

        assert!((bank.current(idx1) - 1.0).abs() < 0.01);
        assert!((bank.current(idx2) - 0.75).abs() < 0.01);
    }
}
