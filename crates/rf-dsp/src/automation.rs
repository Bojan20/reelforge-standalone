//! Sample-Accurate Automation System
//!
//! Provides sample-accurate parameter automation with:
//! - Multiple curve types (linear, exponential, logarithmic, S-curve, step)
//! - Per-sample interpolation
//! - Lock-free parameter updates
//! - Pre-allocated point storage (no allocation in audio thread)

use rf_core::Sample;
use std::sync::atomic::{AtomicU64, Ordering};

// ============ Curve Types ============

/// Automation curve interpolation type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum CurveType {
    /// Linear interpolation (constant rate of change)
    #[default]
    Linear,
    /// Exponential curve (slow start, fast end)
    Exponential,
    /// Logarithmic curve (fast start, slow end)
    Logarithmic,
    /// S-curve (slow start and end, fast middle)
    SCurve,
    /// Step (instant change at point)
    Step,
    /// Hold (maintain value until next point)
    Hold,
    /// Bezier with control point
    Bezier,
}

impl CurveType {
    /// Interpolate between two values using this curve type
    /// t: normalized position (0.0 to 1.0)
    #[inline]
    pub fn interpolate(self, start: f64, end: f64, t: f64) -> f64 {
        let t = t.clamp(0.0, 1.0);

        let shaped_t = match self {
            CurveType::Linear => t,
            CurveType::Exponential => t * t,
            CurveType::Logarithmic => t.sqrt(),
            CurveType::SCurve => t * t * (3.0 - 2.0 * t), // Smoothstep
            CurveType::Step => if t >= 0.5 { 1.0 } else { 0.0 },
            CurveType::Hold => 0.0, // Always use start value
            CurveType::Bezier => t * t * (3.0 - 2.0 * t), // Default to smoothstep
        };

        start + (end - start) * shaped_t
    }

    /// Interpolate with tension parameter (-1.0 to 1.0)
    /// Negative tension: more linear, Positive tension: more curved
    #[inline]
    pub fn interpolate_with_tension(self, start: f64, end: f64, t: f64, tension: f64) -> f64 {
        let t = t.clamp(0.0, 1.0);
        let tension = tension.clamp(-1.0, 1.0);

        // Blend between linear and curved based on tension
        let linear_t = t;
        let curved_t = match self {
            CurveType::Exponential => t.powf(2.0 + tension),
            CurveType::Logarithmic => t.powf(1.0 / (2.0 + tension)),
            CurveType::SCurve => {
                let k = 2.0 + tension * 2.0;
                t.powf(k) / (t.powf(k) + (1.0 - t).powf(k))
            }
            _ => self.interpolate(0.0, 1.0, t),
        };

        let blend = (tension + 1.0) / 2.0;
        let shaped_t = linear_t * (1.0 - blend) + curved_t * blend;

        start + (end - start) * shaped_t
    }
}

// ============ Automation Point ============

/// Single automation point
#[derive(Debug, Clone, Copy)]
#[repr(C, align(32))]
pub struct AutomationPoint {
    /// Sample position (absolute from session start)
    pub sample_position: u64,
    /// Parameter value at this point
    pub value: f64,
    /// Curve type to next point
    pub curve: CurveType,
    /// Curve tension (-1.0 to 1.0)
    pub tension: f64,
}

impl Default for AutomationPoint {
    fn default() -> Self {
        Self {
            sample_position: 0,
            value: 0.0,
            curve: CurveType::Linear,
            tension: 0.0,
        }
    }
}

// ============ Automation Lane ============

/// Maximum points per automation lane (pre-allocated)
pub const MAX_AUTOMATION_POINTS: usize = 4096;

/// Sample-accurate automation lane for a single parameter
#[derive(Debug)]
pub struct AutomationLane {
    /// Sorted array of automation points
    points: Box<[AutomationPoint; MAX_AUTOMATION_POINTS]>,
    /// Number of active points
    point_count: usize,
    /// Parameter ID this lane controls
    param_id: u32,
    /// Default value when no automation
    default_value: f64,
    /// Current playback position for optimization
    current_index: usize,
    /// Minimum value (for clamping)
    min_value: f64,
    /// Maximum value (for clamping)
    max_value: f64,
}

impl AutomationLane {
    /// Create new automation lane with default value
    pub fn new(param_id: u32, default_value: f64, min: f64, max: f64) -> Self {
        Self {
            points: Box::new([AutomationPoint::default(); MAX_AUTOMATION_POINTS]),
            point_count: 0,
            param_id,
            default_value,
            current_index: 0,
            min_value: min,
            max_value: max,
        }
    }

    /// Get parameter ID
    #[inline]
    pub fn param_id(&self) -> u32 {
        self.param_id
    }

    /// Get point count
    #[inline]
    pub fn point_count(&self) -> usize {
        self.point_count
    }

    /// Clear all automation points
    pub fn clear(&mut self) {
        self.point_count = 0;
        self.current_index = 0;
    }

    /// Add an automation point (maintains sorted order)
    /// Returns false if lane is full
    pub fn add_point(&mut self, point: AutomationPoint) -> bool {
        if self.point_count >= MAX_AUTOMATION_POINTS {
            return false;
        }

        // Find insertion position (binary search)
        let pos = match self.points[..self.point_count]
            .binary_search_by_key(&point.sample_position, |p| p.sample_position)
        {
            Ok(pos) => {
                // Replace existing point at same position
                self.points[pos] = point;
                return true;
            }
            Err(pos) => pos,
        };

        // Shift points to make room
        if pos < self.point_count {
            self.points.copy_within(pos..self.point_count, pos + 1);
        }

        self.points[pos] = point;
        self.point_count += 1;
        true
    }

    /// Remove point at index
    pub fn remove_point(&mut self, index: usize) -> bool {
        if index >= self.point_count {
            return false;
        }

        // Shift points down
        if index + 1 < self.point_count {
            self.points.copy_within(index + 1..self.point_count, index);
        }

        self.point_count -= 1;

        // Adjust current index if needed
        if self.current_index > index && self.current_index > 0 {
            self.current_index -= 1;
        }

        true
    }

    /// Get value at exact sample position
    #[inline]
    pub fn value_at_sample(&self, sample_position: u64) -> f64 {
        if self.point_count == 0 {
            return self.default_value;
        }

        let points = &self.points[..self.point_count];

        // Before first point
        if sample_position <= points[0].sample_position {
            return points[0].value;
        }

        // After last point
        if sample_position >= points[self.point_count - 1].sample_position {
            return points[self.point_count - 1].value;
        }

        // Binary search for surrounding points
        let idx = match points.binary_search_by_key(&sample_position, |p| p.sample_position) {
            Ok(idx) => return points[idx].value,
            Err(idx) => idx - 1,
        };

        let p1 = &points[idx];
        let p2 = &points[idx + 1];

        // Interpolate between p1 and p2
        let duration = (p2.sample_position - p1.sample_position) as f64;
        let t = (sample_position - p1.sample_position) as f64 / duration;

        let value = p1.curve.interpolate_with_tension(p1.value, p2.value, t, p1.tension);
        value.clamp(self.min_value, self.max_value)
    }

    /// Get value at sample position with index hint optimization
    /// Call reset_playback() when seeking
    #[inline]
    pub fn value_at_sample_optimized(&mut self, sample_position: u64) -> f64 {
        if self.point_count == 0 {
            return self.default_value;
        }

        let points = &self.points[..self.point_count];

        // Check if we need to search
        if self.current_index >= self.point_count {
            self.current_index = 0;
        }

        // Walk forward from current position (common case: sequential playback)
        while self.current_index + 1 < self.point_count
            && sample_position >= points[self.current_index + 1].sample_position
        {
            self.current_index += 1;
        }

        // Walk backward if needed (seeking backward)
        while self.current_index > 0
            && sample_position < points[self.current_index].sample_position
        {
            self.current_index -= 1;
        }

        // Before first point
        if sample_position <= points[0].sample_position {
            return points[0].value;
        }

        // After last point
        if sample_position >= points[self.point_count - 1].sample_position {
            return points[self.point_count - 1].value;
        }

        let p1 = &points[self.current_index];
        let p2 = &points[self.current_index + 1];

        // Interpolate
        let duration = (p2.sample_position - p1.sample_position) as f64;
        let t = (sample_position - p1.sample_position) as f64 / duration;

        let value = p1.curve.interpolate_with_tension(p1.value, p2.value, t, p1.tension);
        value.clamp(self.min_value, self.max_value)
    }

    /// Reset playback position (call when seeking)
    pub fn reset_playback(&mut self) {
        self.current_index = 0;
    }

    /// Fill buffer with automation values (sample-accurate)
    /// start_sample: absolute sample position at buffer[0]
    pub fn fill_buffer(&mut self, buffer: &mut [Sample], start_sample: u64) {
        for (i, sample) in buffer.iter_mut().enumerate() {
            *sample = self.value_at_sample_optimized(start_sample + i as u64);
        }
    }

    /// Get all active points (for display/editing)
    pub fn points(&self) -> &[AutomationPoint] {
        &self.points[..self.point_count]
    }
}

// ============ Automation Manager ============

/// Manages multiple automation lanes
#[derive(Debug)]
pub struct AutomationManager {
    lanes: Vec<AutomationLane>,
    sample_rate: f64,
}

impl AutomationManager {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            lanes: Vec::with_capacity(64),
            sample_rate,
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    /// Add new automation lane
    pub fn add_lane(&mut self, param_id: u32, default_value: f64, min: f64, max: f64) -> usize {
        let index = self.lanes.len();
        self.lanes.push(AutomationLane::new(param_id, default_value, min, max));
        index
    }

    /// Get lane by index
    pub fn lane(&self, index: usize) -> Option<&AutomationLane> {
        self.lanes.get(index)
    }

    /// Get mutable lane by index
    pub fn lane_mut(&mut self, index: usize) -> Option<&mut AutomationLane> {
        self.lanes.get_mut(index)
    }

    /// Find lane by parameter ID
    pub fn find_lane(&self, param_id: u32) -> Option<&AutomationLane> {
        self.lanes.iter().find(|l| l.param_id() == param_id)
    }

    /// Find mutable lane by parameter ID
    pub fn find_lane_mut(&mut self, param_id: u32) -> Option<&mut AutomationLane> {
        self.lanes.iter_mut().find(|l| l.param_id() == param_id)
    }

    /// Reset all lanes for seeking
    pub fn reset_all(&mut self) {
        for lane in &mut self.lanes {
            lane.reset_playback();
        }
    }

    /// Convert time (seconds) to sample position
    #[inline]
    pub fn time_to_samples(&self, time_seconds: f64) -> u64 {
        (time_seconds * self.sample_rate) as u64
    }

    /// Convert sample position to time (seconds)
    #[inline]
    pub fn samples_to_time(&self, samples: u64) -> f64 {
        samples as f64 / self.sample_rate
    }
}

// ============ Real-Time Automation Reader ============

/// Lock-free automation reader for audio thread
/// Uses atomic snapshot of current value
#[derive(Debug)]
pub struct AtomicAutomationValue {
    /// Current value as atomic bits
    bits: AtomicU64,
    /// Default value
    default: f64,
}

impl AtomicAutomationValue {
    pub fn new(default: f64) -> Self {
        Self {
            bits: AtomicU64::new(default.to_bits()),
            default,
        }
    }

    /// Get current value (audio thread safe)
    #[inline]
    pub fn get(&self) -> f64 {
        f64::from_bits(self.bits.load(Ordering::Relaxed))
    }

    /// Set value (UI thread)
    #[inline]
    pub fn set(&self, value: f64) {
        self.bits.store(value.to_bits(), Ordering::Relaxed);
    }

    /// Reset to default
    pub fn reset(&self) {
        self.set(self.default);
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear_interpolation() {
        let value = CurveType::Linear.interpolate(0.0, 100.0, 0.5);
        assert!((value - 50.0).abs() < 1e-10);
    }

    #[test]
    fn test_exponential_interpolation() {
        // Exponential: t^2, so at t=0.5, result should be 0.25
        let value = CurveType::Exponential.interpolate(0.0, 100.0, 0.5);
        assert!((value - 25.0).abs() < 1e-10);
    }

    #[test]
    fn test_step_interpolation() {
        let before = CurveType::Step.interpolate(0.0, 100.0, 0.4);
        let after = CurveType::Step.interpolate(0.0, 100.0, 0.6);
        assert!((before - 0.0).abs() < 1e-10);
        assert!((after - 100.0).abs() < 1e-10);
    }

    #[test]
    fn test_automation_lane() {
        let mut lane = AutomationLane::new(0, 0.0, 0.0, 1.0);

        // Add points
        lane.add_point(AutomationPoint {
            sample_position: 0,
            value: 0.0,
            curve: CurveType::Linear,
            tension: 0.0,
        });
        lane.add_point(AutomationPoint {
            sample_position: 1000,
            value: 1.0,
            curve: CurveType::Linear,
            tension: 0.0,
        });

        assert_eq!(lane.point_count(), 2);

        // Test interpolation
        let value_start = lane.value_at_sample(0);
        let value_mid = lane.value_at_sample(500);
        let value_end = lane.value_at_sample(1000);

        assert!((value_start - 0.0).abs() < 1e-10);
        assert!((value_mid - 0.5).abs() < 1e-10);
        assert!((value_end - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_atomic_automation_value() {
        let value = AtomicAutomationValue::new(0.5);
        assert!((value.get() - 0.5).abs() < 1e-10);

        value.set(0.75);
        assert!((value.get() - 0.75).abs() < 1e-10);

        value.reset();
        assert!((value.get() - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_fill_buffer() {
        let mut lane = AutomationLane::new(0, 0.5, 0.0, 1.0);
        lane.add_point(AutomationPoint {
            sample_position: 0,
            value: 0.0,
            curve: CurveType::Linear,
            tension: 0.0,
        });
        lane.add_point(AutomationPoint {
            sample_position: 100,
            value: 1.0,
            curve: CurveType::Linear,
            tension: 0.0,
        });

        let mut buffer = [0.0; 101];
        lane.fill_buffer(&mut buffer, 0);

        // Check start, middle, end
        assert!((buffer[0] - 0.0).abs() < 1e-10);
        assert!((buffer[50] - 0.5).abs() < 1e-10);
        assert!((buffer[100] - 1.0).abs() < 1e-10);
    }
}
