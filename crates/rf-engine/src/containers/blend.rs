//! Blend Container - RTPC-based Crossfade
//!
//! Provides smooth transitions between sounds based on a real-time parameter (RTPC).
//! Each child has an RTPC range and crossfade width for volume interpolation.
//!
//! ## Example
//!
//! ```text
//! RTPC Range:  0.0 ────────────────────────────────── 1.0
//!
//! Child A:     ████████████████░░░░░░░░░░░░░░░░░░░░░
//!              └── rtpc_start=0.0  rtpc_end=0.5
//!
//! Child B:     ░░░░░░░░░░░░░░████████████████████████
//!              └── rtpc_start=0.4  rtpc_end=1.0
//!
//! At RTPC=0.45: Child A volume=0.5, Child B volume=0.5 (crossfade zone)
//! ```

use super::{ChildId, Container, ContainerId, ContainerType};
use smallvec::SmallVec;

/// Maximum children per blend container (stack-allocated)
const MAX_BLEND_CHILDREN: usize = 8;

/// Crossfade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum BlendCurve {
    /// Linear interpolation
    #[default]
    Linear = 0,
    /// Smooth S-curve (ease in/out)
    SCurve = 1,
    /// Equal power (constant loudness)
    EqualPower = 2,
    /// Logarithmic (faster attack)
    Logarithmic = 3,
    /// Exponential (slower attack)
    Exponential = 4,
}

impl BlendCurve {
    /// Create from integer value
    pub fn from_u8(value: u8) -> Self {
        match value {
            1 => BlendCurve::SCurve,
            2 => BlendCurve::EqualPower,
            3 => BlendCurve::Logarithmic,
            4 => BlendCurve::Exponential,
            _ => BlendCurve::Linear,
        }
    }

    /// Apply curve to normalized position (0.0 - 1.0)
    #[inline]
    pub fn apply(&self, t: f64) -> f64 {
        match self {
            BlendCurve::Linear => t,
            BlendCurve::SCurve => {
                // Hermite smoothstep: 3t² - 2t³
                t * t * (3.0 - 2.0 * t)
            }
            BlendCurve::EqualPower => {
                // sin(t * π/2) for constant power
                (t * std::f64::consts::FRAC_PI_2).sin()
            }
            BlendCurve::Logarithmic => {
                // log10(1 + 9t) for fast attack
                (1.0 + 9.0 * t).log10()
            }
            BlendCurve::Exponential => {
                // (10^t - 1) / 9 for slow attack
                (10.0_f64.powf(t) - 1.0) / 9.0
            }
        }
    }
}

/// Blend container child
#[derive(Debug, Clone)]
pub struct BlendChild {
    /// Unique child ID
    pub id: ChildId,
    /// Display name
    pub name: String,
    /// Audio file path
    pub audio_path: Option<String>,
    /// RTPC range start (0.0 - 1.0)
    pub rtpc_start: f64,
    /// RTPC range end (0.0 - 1.0)
    pub rtpc_end: f64,
    /// Crossfade width (0.0 - 0.5)
    pub crossfade_width: f64,
    /// Volume multiplier (0.0 - 1.0)
    pub volume: f64,
}

impl BlendChild {
    /// Create a new blend child
    pub fn new(id: ChildId, name: impl Into<String>, rtpc_start: f64, rtpc_end: f64) -> Self {
        Self {
            id,
            name: name.into(),
            audio_path: None,
            rtpc_start: rtpc_start.clamp(0.0, 1.0),
            rtpc_end: rtpc_end.clamp(0.0, 1.0),
            crossfade_width: 0.1,
            volume: 1.0,
        }
    }

    /// Check if RTPC value is within this child's active range
    #[inline]
    pub fn is_active(&self, rtpc: f64) -> bool {
        rtpc >= self.rtpc_start - self.crossfade_width
            && rtpc <= self.rtpc_end + self.crossfade_width
    }

    /// Calculate volume for given RTPC value
    #[inline]
    pub fn calculate_volume(&self, rtpc: f64, curve: BlendCurve) -> f64 {
        if rtpc < self.rtpc_start - self.crossfade_width
            || rtpc > self.rtpc_end + self.crossfade_width
        {
            return 0.0;
        }

        let fade_in_start = self.rtpc_start - self.crossfade_width;
        let fade_in_end = self.rtpc_start;
        let fade_out_start = self.rtpc_end;
        let fade_out_end = self.rtpc_end + self.crossfade_width;

        let vol = if rtpc < fade_in_end && self.crossfade_width > 0.0 {
            // Fade in zone
            let t = (rtpc - fade_in_start) / (fade_in_end - fade_in_start);
            curve.apply(t.clamp(0.0, 1.0))
        } else if rtpc > fade_out_start && self.crossfade_width > 0.0 {
            // Fade out zone
            let t = (fade_out_end - rtpc) / (fade_out_end - fade_out_start);
            curve.apply(t.clamp(0.0, 1.0))
        } else {
            // Full volume zone
            1.0
        };

        vol * self.volume
    }
}

/// Blend container
#[derive(Debug, Clone)]
pub struct BlendContainer {
    /// Unique container ID
    pub id: ContainerId,
    /// Display name
    pub name: String,
    /// Whether container is enabled
    pub enabled: bool,
    /// Current RTPC value (0.0 - 1.0)
    pub rtpc_value: f64,
    /// Target RTPC value for smoothing
    rtpc_target: f64,
    /// RTPC parameter name (for binding)
    pub rtpc_name: String,
    /// Crossfade curve type
    pub curve: BlendCurve,
    /// Child sounds
    pub children: SmallVec<[BlendChild; MAX_BLEND_CHILDREN]>,

    // P3D: Parameter smoothing
    /// Smoothing time in milliseconds (0 = instant)
    pub smoothing_ms: f64,
    /// Current smoothing velocity (for inertia)
    smoothing_velocity: f64,
}

impl BlendContainer {
    /// Create a new blend container
    pub fn new(id: ContainerId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            enabled: true,
            rtpc_value: 0.5,
            rtpc_target: 0.5,
            rtpc_name: String::new(),
            curve: BlendCurve::Linear,
            children: SmallVec::new(),
            smoothing_ms: 0.0,
            smoothing_velocity: 0.0,
        }
    }

    /// Add a child to the container
    pub fn add_child(&mut self, child: BlendChild) {
        self.children.push(child);
    }

    /// Remove a child by ID
    pub fn remove_child(&mut self, child_id: ChildId) -> bool {
        if let Some(pos) = self.children.iter().position(|c| c.id == child_id) {
            self.children.remove(pos);
            true
        } else {
            false
        }
    }

    /// Set RTPC value (instant, bypasses smoothing)
    #[inline]
    pub fn set_rtpc(&mut self, value: f64) {
        let v = value.clamp(0.0, 1.0);
        self.rtpc_value = v;
        self.rtpc_target = v;
        self.smoothing_velocity = 0.0;
    }

    /// Set RTPC target value (will smoothly interpolate if smoothing_ms > 0)
    #[inline]
    pub fn set_rtpc_target(&mut self, value: f64) {
        self.rtpc_target = value.clamp(0.0, 1.0);
    }

    /// Set smoothing time in milliseconds
    #[inline]
    pub fn set_smoothing_ms(&mut self, ms: f64) {
        self.smoothing_ms = ms.max(0.0);
    }

    /// Update RTPC smoothing by delta time (in milliseconds)
    /// Call this every tick/frame for smooth interpolation
    /// Returns true if value changed
    #[inline]
    pub fn tick_smoothing(&mut self, delta_ms: f64) -> bool {
        if self.smoothing_ms <= 0.0 || (self.rtpc_value - self.rtpc_target).abs() < 0.0001 {
            // Instant or already at target
            if (self.rtpc_value - self.rtpc_target).abs() >= 0.0001 {
                self.rtpc_value = self.rtpc_target;
                self.smoothing_velocity = 0.0;
                return true;
            }
            return false;
        }

        // Critically damped spring for smooth, overshoot-free interpolation
        // Based on: https://www.ryanjuckett.com/damped-springs/
        let omega = 2.0 * std::f64::consts::PI / (self.smoothing_ms / 1000.0);
        let zeta = 1.0; // Critically damped

        let delta_s = delta_ms / 1000.0;
        let x = self.rtpc_value - self.rtpc_target;
        let v = self.smoothing_velocity;

        let exp_term = (-zeta * omega * delta_s).exp();
        let cos_term = (omega * delta_s).cos();
        let sin_term = (omega * delta_s).sin();

        // Simplified critically damped response
        let new_x = exp_term * (x * cos_term + (v + zeta * omega * x) * sin_term / omega);
        let new_v =
            exp_term * (v * cos_term - (v * zeta * omega + omega * omega * x) * sin_term / omega);

        self.rtpc_value = self.rtpc_target + new_x;
        self.smoothing_velocity = new_v;

        // Snap to target if very close
        if (self.rtpc_value - self.rtpc_target).abs() < 0.0001 {
            self.rtpc_value = self.rtpc_target;
            self.smoothing_velocity = 0.0;
        }

        true
    }

    /// Get current smoothed RTPC value
    #[inline]
    pub fn smoothed_rtpc(&self) -> f64 {
        self.rtpc_value
    }

    /// Get target RTPC value
    #[inline]
    pub fn target_rtpc(&self) -> f64 {
        self.rtpc_target
    }

    /// Check if currently smoothing
    #[inline]
    pub fn is_smoothing(&self) -> bool {
        self.smoothing_ms > 0.0 && (self.rtpc_value - self.rtpc_target).abs() >= 0.0001
    }

    /// Evaluate blend at current RTPC value
    /// Returns list of (child_id, volume) pairs for active children
    pub fn evaluate(&self) -> BlendResult {
        if !self.enabled || self.children.is_empty() {
            return BlendResult::default();
        }

        let mut result = BlendResult::default();

        for child in &self.children {
            let volume = child.calculate_volume(self.rtpc_value, self.curve);
            if volume > 0.001 {
                // Skip inaudible
                result.children.push((child.id, volume));
            }
        }

        result
    }

    /// Evaluate blend at specific RTPC value
    pub fn evaluate_at(&self, rtpc: f64) -> BlendResult {
        if !self.enabled || self.children.is_empty() {
            return BlendResult::default();
        }

        let mut result = BlendResult::default();

        for child in &self.children {
            let volume = child.calculate_volume(rtpc, self.curve);
            if volume > 0.001 {
                result.children.push((child.id, volume));
            }
        }

        result
    }

    /// Get child by ID
    pub fn get_child(&self, child_id: ChildId) -> Option<&BlendChild> {
        self.children.iter().find(|c| c.id == child_id)
    }

    /// Get mutable child by ID
    pub fn get_child_mut(&mut self, child_id: ChildId) -> Option<&mut BlendChild> {
        self.children.iter_mut().find(|c| c.id == child_id)
    }
}

impl Container for BlendContainer {
    fn id(&self) -> ContainerId {
        self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn is_enabled(&self) -> bool {
        self.enabled
    }

    fn container_type(&self) -> ContainerType {
        ContainerType::Blend
    }

    fn child_count(&self) -> usize {
        self.children.len()
    }
}

/// Result of blend evaluation
#[derive(Debug, Clone, Default)]
pub struct BlendResult {
    /// Active children with their volumes: (child_id, volume)
    pub children: SmallVec<[(ChildId, f64); MAX_BLEND_CHILDREN]>,
}

impl BlendResult {
    /// Check if any children are active
    pub fn is_empty(&self) -> bool {
        self.children.is_empty()
    }

    /// Get total number of active children
    pub fn len(&self) -> usize {
        self.children.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blend_curve_linear() {
        let curve = BlendCurve::Linear;
        assert!((curve.apply(0.0) - 0.0).abs() < 0.001);
        assert!((curve.apply(0.5) - 0.5).abs() < 0.001);
        assert!((curve.apply(1.0) - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_blend_curve_scurve() {
        let curve = BlendCurve::SCurve;
        assert!((curve.apply(0.0) - 0.0).abs() < 0.001);
        assert!((curve.apply(0.5) - 0.5).abs() < 0.001);
        assert!((curve.apply(1.0) - 1.0).abs() < 0.001);
        // S-curve should be slower at edges
        assert!(curve.apply(0.25) < 0.25);
        assert!(curve.apply(0.75) > 0.75);
    }

    #[test]
    fn test_blend_child_volume() {
        let child = BlendChild::new(1, "test", 0.3, 0.7);

        // Outside range
        assert!((child.calculate_volume(0.0, BlendCurve::Linear)).abs() < 0.001);
        assert!((child.calculate_volume(1.0, BlendCurve::Linear)).abs() < 0.001);

        // Inside range (full volume)
        assert!((child.calculate_volume(0.5, BlendCurve::Linear) - 1.0).abs() < 0.001);

        // Crossfade zones
        let vol_fade_in = child.calculate_volume(0.25, BlendCurve::Linear);
        assert!(vol_fade_in > 0.0 && vol_fade_in < 1.0);
    }

    #[test]
    fn test_blend_container_evaluate() {
        let mut container = BlendContainer::new(1, "test_blend");

        // Add two children with overlapping ranges
        container.add_child(BlendChild::new(1, "low", 0.0, 0.5));
        container.add_child(BlendChild::new(2, "high", 0.4, 1.0));

        // At RTPC=0.2, only "low" should be active
        container.set_rtpc(0.2);
        let result = container.evaluate();
        assert_eq!(result.len(), 1);

        // At RTPC=0.45, both should be active (crossfade zone)
        container.set_rtpc(0.45);
        let result = container.evaluate();
        assert_eq!(result.len(), 2);

        // At RTPC=0.8, only "high" should be active
        container.set_rtpc(0.8);
        let result = container.evaluate();
        assert_eq!(result.len(), 1);
    }
}
