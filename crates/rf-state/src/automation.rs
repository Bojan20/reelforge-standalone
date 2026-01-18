//! Parameter automation

use rf_core::{ParamId, SamplePosition};
use serde::{Deserialize, Serialize};

/// Automation point
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct AutomationPoint {
    pub position: u64,
    pub value: f64,
    pub curve: CurveType,
}

/// Curve type between automation points
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[derive(Default)]
pub enum CurveType {
    #[default]
    Linear,
    Step,
    Exponential,
    Logarithmic,
    SCurve,
}


/// Automation lane for a single parameter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationLane {
    pub param_id: u32,
    pub points: Vec<AutomationPoint>,
    pub enabled: bool,
}

impl AutomationLane {
    pub fn new(param_id: ParamId) -> Self {
        Self {
            param_id: param_id.0,
            points: Vec::new(),
            enabled: true,
        }
    }

    /// Add a point to the lane
    pub fn add_point(&mut self, position: u64, value: f64, curve: CurveType) {
        let point = AutomationPoint {
            position,
            value,
            curve,
        };

        // Insert in sorted order
        let idx = self
            .points
            .binary_search_by(|p| p.position.cmp(&position))
            .unwrap_or_else(|i| i);

        self.points.insert(idx, point);
    }

    /// Remove point at index
    pub fn remove_point(&mut self, index: usize) -> Option<AutomationPoint> {
        if index < self.points.len() {
            Some(self.points.remove(index))
        } else {
            None
        }
    }

    /// Get value at a specific position
    pub fn value_at(&self, position: u64) -> Option<f64> {
        if self.points.is_empty() {
            return None;
        }

        // Find surrounding points
        let idx = self
            .points
            .binary_search_by(|p| p.position.cmp(&position))
            .unwrap_or_else(|i| i);

        if idx == 0 {
            // Before first point
            return Some(self.points[0].value);
        }

        if idx >= self.points.len() {
            // After last point
            return Some(self.points.last().unwrap().value);
        }

        let p1 = &self.points[idx - 1];
        let p2 = &self.points[idx];

        // Interpolate based on curve type
        let t = (position - p1.position) as f64 / (p2.position - p1.position) as f64;

        Some(interpolate(p1.value, p2.value, t, p1.curve))
    }

    /// Get value at sample position (sample-accurate)
    pub fn value_at_sample(&self, position: SamplePosition) -> Option<f64> {
        self.value_at(position.0)
    }

    /// Clear all points
    pub fn clear(&mut self) {
        self.points.clear();
    }

    /// Get number of points
    pub fn len(&self) -> usize {
        self.points.len()
    }

    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }
}

/// Interpolate between two values
fn interpolate(v1: f64, v2: f64, t: f64, curve: CurveType) -> f64 {
    match curve {
        CurveType::Linear => v1 + (v2 - v1) * t,
        CurveType::Step => v1,
        CurveType::Exponential => {
            let t_exp = t * t;
            v1 + (v2 - v1) * t_exp
        }
        CurveType::Logarithmic => {
            let t_log = t.sqrt();
            v1 + (v2 - v1) * t_log
        }
        CurveType::SCurve => {
            let t_s = t * t * (3.0 - 2.0 * t);
            v1 + (v2 - v1) * t_s
        }
    }
}

/// Automation playback state
pub struct AutomationPlayer {
    lanes: Vec<AutomationLane>,
    position: SamplePosition,
    playing: bool,
}

impl AutomationPlayer {
    pub fn new() -> Self {
        Self {
            lanes: Vec::new(),
            position: SamplePosition::ZERO,
            playing: false,
        }
    }

    pub fn add_lane(&mut self, lane: AutomationLane) {
        self.lanes.push(lane);
    }

    pub fn get_lane(&self, param_id: ParamId) -> Option<&AutomationLane> {
        self.lanes.iter().find(|l| l.param_id == param_id.0)
    }

    pub fn get_lane_mut(&mut self, param_id: ParamId) -> Option<&mut AutomationLane> {
        self.lanes.iter_mut().find(|l| l.param_id == param_id.0)
    }

    pub fn set_position(&mut self, position: SamplePosition) {
        self.position = position;
    }

    pub fn advance(&mut self, samples: u64) {
        self.position.advance(samples);
    }

    pub fn play(&mut self) {
        self.playing = true;
    }

    pub fn stop(&mut self) {
        self.playing = false;
    }

    pub fn is_playing(&self) -> bool {
        self.playing
    }

    /// Get all parameter values at current position
    pub fn current_values(&self) -> Vec<(ParamId, f64)> {
        self.lanes
            .iter()
            .filter(|l| l.enabled)
            .filter_map(|l| {
                l.value_at_sample(self.position)
                    .map(|v| (ParamId(l.param_id), v))
            })
            .collect()
    }
}

impl Default for AutomationPlayer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_automation_lane() {
        let mut lane = AutomationLane::new(ParamId(0));

        lane.add_point(0, 0.0, CurveType::Linear);
        lane.add_point(100, 1.0, CurveType::Linear);

        assert_eq!(lane.value_at(0), Some(0.0));
        assert_eq!(lane.value_at(100), Some(1.0));

        // Linear interpolation at midpoint
        let mid = lane.value_at(50).unwrap();
        assert!((mid - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_step_curve() {
        let mut lane = AutomationLane::new(ParamId(0));

        lane.add_point(0, 0.0, CurveType::Step);
        lane.add_point(100, 1.0, CurveType::Step);

        // Step should hold first value until next point
        assert_eq!(lane.value_at(50), Some(0.0));
        assert_eq!(lane.value_at(99), Some(0.0));
    }
}
