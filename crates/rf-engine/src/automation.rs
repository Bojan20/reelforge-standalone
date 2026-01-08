//! Automation Engine
//!
//! Sample-accurate parameter automation system:
//! - Bezier curve interpolation
//! - Touch/Latch/Write modes
//! - Automation lanes per parameter
//! - Real-time recording and playback

use std::collections::HashMap;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

// TrackId, ClipId defined locally in track_manager

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION POINT
// ═══════════════════════════════════════════════════════════════════════════

/// Automation curve type
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub enum CurveType {
    /// Linear interpolation
    #[default]
    Linear,
    /// Bezier curve (smooth)
    Bezier,
    /// Exponential curve
    Exponential,
    /// Logarithmic curve
    Logarithmic,
    /// Step (hold until next point)
    Step,
    /// S-Curve (smooth sigmoid)
    SCurve,
}

/// Single automation point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationPoint {
    /// Time in samples from start
    pub time_samples: u64,
    /// Normalized value (0.0 - 1.0)
    pub value: f64,
    /// Curve type to next point
    pub curve: CurveType,
    /// Bezier control point 1 (relative, 0-1 in both axes)
    pub bezier_cp1: Option<(f64, f64)>,
    /// Bezier control point 2 (relative, 0-1 in both axes)
    pub bezier_cp2: Option<(f64, f64)>,
}

impl AutomationPoint {
    pub fn new(time_samples: u64, value: f64) -> Self {
        Self {
            time_samples,
            value: value.clamp(0.0, 1.0),
            curve: CurveType::Linear,
            bezier_cp1: None,
            bezier_cp2: None,
        }
    }

    pub fn with_curve(mut self, curve: CurveType) -> Self {
        self.curve = curve;
        self
    }

    pub fn with_bezier(mut self, cp1: (f64, f64), cp2: (f64, f64)) -> Self {
        self.curve = CurveType::Bezier;
        self.bezier_cp1 = Some(cp1);
        self.bezier_cp2 = Some(cp2);
        self
    }

    /// Time in seconds (given sample rate)
    pub fn time_secs(&self, sample_rate: f64) -> f64 {
        self.time_samples as f64 / sample_rate
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION LANE
// ═══════════════════════════════════════════════════════════════════════════

/// Parameter identifier
#[derive(Debug, Clone, Hash, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParamId {
    /// Track or bus ID
    pub target_id: u64,
    /// Target type
    pub target_type: TargetType,
    /// Parameter name/index
    pub param_name: String,
    /// Plugin slot (if applicable)
    pub slot: Option<u32>,
}

/// Target type for automation
#[derive(Debug, Clone, Copy, Hash, PartialEq, Eq, Serialize, Deserialize)]
pub enum TargetType {
    Track,
    Bus,
    Master,
    Plugin,
    Send,
    Clip,
}

impl ParamId {
    pub fn track_volume(track_id: u64) -> Self {
        Self {
            target_id: track_id,
            target_type: TargetType::Track,
            param_name: "volume".to_string(),
            slot: None,
        }
    }

    pub fn track_pan(track_id: u64) -> Self {
        Self {
            target_id: track_id,
            target_type: TargetType::Track,
            param_name: "pan".to_string(),
            slot: None,
        }
    }

    pub fn track_mute(track_id: u64) -> Self {
        Self {
            target_id: track_id,
            target_type: TargetType::Track,
            param_name: "mute".to_string(),
            slot: None,
        }
    }

    pub fn plugin_param(track_id: u64, slot: u32, param_name: &str) -> Self {
        Self {
            target_id: track_id,
            target_type: TargetType::Plugin,
            param_name: param_name.to_string(),
            slot: Some(slot),
        }
    }

    pub fn send_level(track_id: u64, send_slot: u32) -> Self {
        Self {
            target_id: track_id,
            target_type: TargetType::Send,
            param_name: "level".to_string(),
            slot: Some(send_slot),
        }
    }
}

/// Automation lane for a single parameter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationLane {
    /// Parameter ID
    pub param_id: ParamId,
    /// Display name
    pub name: String,
    /// Automation points (sorted by time)
    pub points: Vec<AutomationPoint>,
    /// Is lane enabled
    pub enabled: bool,
    /// Is lane visible in UI
    pub visible: bool,
    /// Default value when no automation
    pub default_value: f64,
    /// Min/max for UI display
    pub min_value: f64,
    pub max_value: f64,
    /// Value suffix (e.g., "dB", "%")
    pub unit: String,
}

impl AutomationLane {
    pub fn new(param_id: ParamId, name: &str) -> Self {
        Self {
            param_id,
            name: name.to_string(),
            points: Vec::new(),
            enabled: true,
            visible: true,
            default_value: 0.5,
            min_value: 0.0,
            max_value: 1.0,
            unit: String::new(),
        }
    }

    pub fn with_range(mut self, min: f64, max: f64, default: f64) -> Self {
        self.min_value = min;
        self.max_value = max;
        self.default_value = default;
        self
    }

    pub fn with_unit(mut self, unit: &str) -> Self {
        self.unit = unit.to_string();
        self
    }

    /// Add a point, maintaining sorted order
    pub fn add_point(&mut self, point: AutomationPoint) {
        let idx = self.points
            .binary_search_by_key(&point.time_samples, |p| p.time_samples)
            .unwrap_or_else(|i| i);
        self.points.insert(idx, point);
    }

    /// Remove point at time (within tolerance)
    pub fn remove_point_at(&mut self, time_samples: u64, tolerance: u64) -> bool {
        if let Some(idx) = self.points.iter().position(|p| {
            (p.time_samples as i64 - time_samples as i64).abs() <= tolerance as i64
        }) {
            self.points.remove(idx);
            true
        } else {
            false
        }
    }

    /// Get value at sample position (interpolated)
    pub fn value_at(&self, time_samples: u64) -> f64 {
        if self.points.is_empty() {
            return self.default_value;
        }

        // Before first point
        if time_samples <= self.points[0].time_samples {
            return self.points[0].value;
        }

        // After last point
        if time_samples >= self.points.last().unwrap().time_samples {
            return self.points.last().unwrap().value;
        }

        // Find surrounding points
        let idx = self.points
            .binary_search_by_key(&time_samples, |p| p.time_samples)
            .unwrap_or_else(|i| i);

        if idx == 0 {
            return self.points[0].value;
        }

        let p1 = &self.points[idx - 1];
        let p2 = &self.points[idx];

        // Interpolation factor
        let t = (time_samples - p1.time_samples) as f64
            / (p2.time_samples - p1.time_samples) as f64;

        self.interpolate(p1, p2, t)
    }

    /// Interpolate between two points
    fn interpolate(&self, p1: &AutomationPoint, p2: &AutomationPoint, t: f64) -> f64 {
        match p1.curve {
            CurveType::Linear => {
                p1.value + (p2.value - p1.value) * t
            }
            CurveType::Step => {
                p1.value
            }
            CurveType::Exponential => {
                let exp_t = t * t;
                p1.value + (p2.value - p1.value) * exp_t
            }
            CurveType::Logarithmic => {
                let log_t = t.sqrt();
                p1.value + (p2.value - p1.value) * log_t
            }
            CurveType::SCurve => {
                // Smooth sigmoid S-curve
                let s = t * t * (3.0 - 2.0 * t);
                p1.value + (p2.value - p1.value) * s
            }
            CurveType::Bezier => {
                self.bezier_interpolate(p1, p2, t)
            }
        }
    }

    /// Cubic bezier interpolation
    fn bezier_interpolate(&self, p1: &AutomationPoint, p2: &AutomationPoint, t: f64) -> f64 {
        let cp1 = p1.bezier_cp1.unwrap_or((0.33, 0.0));
        let cp2 = p1.bezier_cp2.unwrap_or((0.66, 0.0));

        // Control points in absolute coordinates
        let y0 = p1.value;
        let y3 = p2.value;
        let y1 = y0 + cp1.1 * (y3 - y0);
        let y2 = y0 + cp2.1 * (y3 - y0);

        // Cubic bezier formula
        let t2 = t * t;
        let t3 = t2 * t;
        let mt = 1.0 - t;
        let mt2 = mt * mt;
        let mt3 = mt2 * mt;

        mt3 * y0 + 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3 * y3
    }

    /// Get all points in time range
    pub fn points_in_range(&self, start: u64, end: u64) -> Vec<&AutomationPoint> {
        self.points.iter()
            .filter(|p| p.time_samples >= start && p.time_samples <= end)
            .collect()
    }

    /// Clear all points
    pub fn clear(&mut self) {
        self.points.clear();
    }

    /// Scale all values
    pub fn scale_values(&mut self, factor: f64) {
        for point in &mut self.points {
            point.value = (point.value * factor).clamp(0.0, 1.0);
        }
    }

    /// Offset all times
    pub fn offset_time(&mut self, offset_samples: i64) {
        for point in &mut self.points {
            if offset_samples >= 0 {
                point.time_samples = point.time_samples.saturating_add(offset_samples as u64);
            } else {
                point.time_samples = point.time_samples.saturating_sub((-offset_samples) as u64);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION MODE
// ═══════════════════════════════════════════════════════════════════════════

/// Automation recording mode
#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub enum AutomationMode {
    /// Automation is read but not written
    #[default]
    Read,
    /// Write automation while parameter is touched
    Touch,
    /// Write automation from touch until stop
    Latch,
    /// Continuously write automation
    Write,
    /// Trim existing automation
    Trim,
    /// Automation is completely off
    Off,
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Parameter change event
#[derive(Debug, Clone)]
pub struct ParamChange {
    pub param_id: ParamId,
    pub value: f64,
    pub time_samples: u64,
}

/// Trim info for automation trim mode
#[derive(Debug, Clone)]
pub struct TrimInfo {
    /// Original automation value at touch start
    pub original_value: f64,
    /// Start position (samples)
    pub start_pos: u64,
    /// Current trim delta
    pub delta: f64,
}

/// Automation engine
pub struct AutomationEngine {
    /// All automation lanes
    lanes: RwLock<HashMap<ParamId, AutomationLane>>,
    /// Current playback position (samples)
    position: std::sync::atomic::AtomicU64,
    /// Sample rate
    sample_rate: f64,
    /// Global automation mode
    mode: RwLock<AutomationMode>,
    /// Per-parameter modes (override global)
    param_modes: RwLock<HashMap<ParamId, AutomationMode>>,
    /// Parameters currently being touched
    touched_params: RwLock<HashMap<ParamId, f64>>,
    /// Pending changes for recording
    pending_changes: RwLock<Vec<ParamChange>>,
    /// Is transport playing
    is_playing: std::sync::atomic::AtomicBool,
    /// Is recording enabled
    is_recording: std::sync::atomic::AtomicBool,
    /// Trim mode info per parameter
    trim_info: RwLock<HashMap<ParamId, TrimInfo>>,
}

impl AutomationEngine {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            lanes: RwLock::new(HashMap::new()),
            position: std::sync::atomic::AtomicU64::new(0),
            sample_rate,
            mode: RwLock::new(AutomationMode::Read),
            param_modes: RwLock::new(HashMap::new()),
            touched_params: RwLock::new(HashMap::new()),
            pending_changes: RwLock::new(Vec::new()),
            is_playing: std::sync::atomic::AtomicBool::new(false),
            is_recording: std::sync::atomic::AtomicBool::new(false),
            trim_info: RwLock::new(HashMap::new()),
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }

    /// Set global automation mode
    pub fn set_mode(&self, mode: AutomationMode) {
        *self.mode.write() = mode;
    }

    /// Get global automation mode
    pub fn mode(&self) -> AutomationMode {
        *self.mode.read()
    }

    /// Set mode for specific parameter
    pub fn set_param_mode(&self, param_id: ParamId, mode: AutomationMode) {
        self.param_modes.write().insert(param_id, mode);
    }

    /// Get mode for specific parameter (falls back to global)
    pub fn param_mode(&self, param_id: &ParamId) -> AutomationMode {
        self.param_modes.read()
            .get(param_id)
            .copied()
            .unwrap_or_else(|| *self.mode.read())
    }

    /// Add or get automation lane
    pub fn get_or_create_lane(&self, param_id: ParamId, name: &str) -> ParamId {
        let mut lanes = self.lanes.write();
        if !lanes.contains_key(&param_id) {
            lanes.insert(param_id.clone(), AutomationLane::new(param_id.clone(), name));
        }
        param_id
    }

    /// Get lane reference
    pub fn lane(&self, param_id: &ParamId) -> Option<AutomationLane> {
        self.lanes.read().get(param_id).cloned()
    }

    /// Modify lane
    pub fn with_lane<F, R>(&self, param_id: &ParamId, f: F) -> Option<R>
    where
        F: FnOnce(&mut AutomationLane) -> R,
    {
        self.lanes.write().get_mut(param_id).map(f)
    }

    /// Add point to lane
    pub fn add_point(&self, param_id: &ParamId, point: AutomationPoint) {
        if let Some(lane) = self.lanes.write().get_mut(param_id) {
            lane.add_point(point);
        }
    }

    /// Set playback position
    pub fn set_position(&self, samples: u64) {
        self.position.store(samples, std::sync::atomic::Ordering::Relaxed);
    }

    /// Get current position
    pub fn position(&self) -> u64 {
        self.position.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Advance position by sample count
    pub fn advance(&self, samples: u64) {
        self.position.fetch_add(samples, std::sync::atomic::Ordering::Relaxed);
    }

    /// Set playing state
    pub fn set_playing(&self, playing: bool) {
        self.is_playing.store(playing, std::sync::atomic::Ordering::Relaxed);
    }

    /// Is playing
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Set recording state
    pub fn set_recording(&self, recording: bool) {
        self.is_recording.store(recording, std::sync::atomic::Ordering::Relaxed);
    }

    /// Is recording
    pub fn is_recording(&self) -> bool {
        self.is_recording.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Get parameter value at current position (for playback)
    pub fn get_value(&self, param_id: &ParamId) -> Option<f64> {
        let mode = self.param_mode(param_id);

        // If automation is off, return None
        if mode == AutomationMode::Off {
            return None;
        }

        // If parameter is touched in Touch/Latch/Write mode, don't read automation
        if matches!(mode, AutomationMode::Touch | AutomationMode::Latch | AutomationMode::Write) {
            if self.touched_params.read().contains_key(param_id) {
                return None;
            }
        }

        // Read automation
        let lanes = self.lanes.read();
        if let Some(lane) = lanes.get(param_id) {
            if lane.enabled && !lane.points.is_empty() {
                let pos = self.position();
                return Some(lane.value_at(pos));
            }
        }

        None
    }

    /// Get parameter value at specific time (for block processing)
    pub fn get_value_at(&self, param_id: &ParamId, time_samples: u64) -> Option<f64> {
        let mode = self.param_mode(param_id);

        if mode == AutomationMode::Off {
            return None;
        }

        let lanes = self.lanes.read();
        if let Some(lane) = lanes.get(param_id) {
            if lane.enabled && !lane.points.is_empty() {
                return Some(lane.value_at(time_samples));
            }
        }

        None
    }

    /// Get interpolated values for a block of samples
    /// Returns Vec of (sample_offset, value) pairs where value changes
    pub fn get_block_values(&self, param_id: &ParamId, start: u64, block_size: usize) -> Vec<(usize, f64)> {
        let mode = self.param_mode(param_id);

        if mode == AutomationMode::Off {
            return Vec::new();
        }

        let lanes = self.lanes.read();
        let lane = match lanes.get(param_id) {
            Some(l) if l.enabled && !l.points.is_empty() => l,
            _ => return Vec::new(),
        };

        let mut changes = Vec::new();
        let end = start + block_size as u64;

        // Get value at start of block
        let start_value = lane.value_at(start);
        changes.push((0, start_value));

        // Find all points within block
        for point in lane.points_in_range(start, end) {
            let offset = (point.time_samples - start) as usize;
            if offset > 0 && offset < block_size {
                changes.push((offset, point.value));
            }
        }

        // For smooth automation, sample at regular intervals
        if lane.points.len() > 1 && changes.len() < 4 {
            // Add intermediate samples for smooth curves
            let step = block_size / 4;
            for i in 1..4 {
                let offset = i * step;
                let time = start + offset as u64;
                let value = lane.value_at(time);
                if !changes.iter().any(|(o, _)| *o == offset) {
                    changes.push((offset, value));
                }
            }
            changes.sort_by_key(|(o, _)| *o);
        }

        changes
    }

    /// Touch parameter (start recording in Touch/Latch/Trim mode)
    pub fn touch_param(&self, param_id: ParamId, current_value: f64) {
        let mode = self.param_mode(&param_id);

        if matches!(mode, AutomationMode::Touch | AutomationMode::Latch | AutomationMode::Write | AutomationMode::Trim) {
            self.touched_params.write().insert(param_id.clone(), current_value);
        }

        // For Trim mode, also record the original automation value and position
        if mode == AutomationMode::Trim {
            let pos = self.position();
            let original = self.lanes.read()
                .get(&param_id)
                .map(|l| l.value_at(pos))
                .unwrap_or(current_value);

            self.trim_info.write().insert(param_id, TrimInfo {
                original_value: original,
                start_pos: pos,
                delta: 0.0,
            });
        }
    }

    /// Release parameter (stop recording in Touch mode, apply trim, continue in Latch)
    pub fn release_param(&self, param_id: &ParamId) {
        let mode = self.param_mode(param_id);

        if mode == AutomationMode::Touch {
            self.touched_params.write().remove(param_id);
            self.commit_pending_changes(param_id);
        } else if mode == AutomationMode::Trim {
            // Apply trim delta to all points in the range
            if let Some(trim) = self.trim_info.write().remove(param_id) {
                let end_pos = self.position();
                self.apply_trim(param_id, trim.start_pos, end_pos, trim.delta);
            }
            self.touched_params.write().remove(param_id);
        }
        // In Latch mode, we don't release until transport stops
    }

    /// Apply trim delta to automation points in range
    fn apply_trim(&self, param_id: &ParamId, start: u64, end: u64, delta: f64) {
        if delta.abs() < 1e-6 {
            return;
        }

        if let Some(lane) = self.lanes.write().get_mut(param_id) {
            for point in lane.points.iter_mut() {
                if point.time_samples >= start && point.time_samples <= end {
                    point.value = (point.value + delta).clamp(0.0, 1.0);
                }
            }
        }
    }

    /// Record parameter change
    pub fn record_change(&self, param_id: ParamId, value: f64) {
        if !self.is_playing() || !self.is_recording() {
            return;
        }

        let mode = self.param_mode(&param_id);

        // Handle Trim mode - update delta instead of recording new points
        if mode == AutomationMode::Trim {
            if self.touched_params.read().contains_key(&param_id) {
                let mut trim_info = self.trim_info.write();
                if let Some(info) = trim_info.get_mut(&param_id) {
                    // Calculate delta from original value to new value
                    info.delta = value - info.original_value;
                }
            }
            return;
        }

        let should_record = match mode {
            AutomationMode::Write => true,
            AutomationMode::Touch | AutomationMode::Latch => {
                self.touched_params.read().contains_key(&param_id)
            }
            _ => false,
        };

        if should_record {
            let change = ParamChange {
                param_id,
                value,
                time_samples: self.position(),
            };
            self.pending_changes.write().push(change);
        }
    }

    /// Commit pending changes to automation lane
    fn commit_pending_changes(&self, param_id: &ParamId) {
        let mut pending = self.pending_changes.write();
        let changes: Vec<_> = pending.drain(..)
            .filter(|c| &c.param_id == param_id)
            .collect();

        if let Some(lane) = self.lanes.write().get_mut(param_id) {
            for change in changes {
                lane.add_point(AutomationPoint::new(change.time_samples, change.value));
            }
        }
    }

    /// Commit all pending changes (call on transport stop)
    pub fn commit_all_pending(&self) {
        let mut pending = self.pending_changes.write();
        let changes: Vec<_> = pending.drain(..).collect();

        let mut lanes = self.lanes.write();
        for change in changes {
            if let Some(lane) = lanes.get_mut(&change.param_id) {
                lane.add_point(AutomationPoint::new(change.time_samples, change.value));
            }
        }

        // Release all touched params in Latch mode
        self.touched_params.write().clear();
    }

    /// Get all lane IDs
    pub fn lane_ids(&self) -> Vec<ParamId> {
        self.lanes.read().keys().cloned().collect()
    }

    /// Remove lane
    pub fn remove_lane(&self, param_id: &ParamId) {
        self.lanes.write().remove(param_id);
    }

    /// Clear all automation
    pub fn clear_all(&self) {
        self.lanes.write().clear();
        self.pending_changes.write().clear();
        self.touched_params.write().clear();
    }

    /// Export lane as serializable data
    pub fn export_lane(&self, param_id: &ParamId) -> Option<AutomationLane> {
        self.lanes.read().get(param_id).cloned()
    }

    /// Import lane
    pub fn import_lane(&self, lane: AutomationLane) {
        self.lanes.write().insert(lane.param_id.clone(), lane);
    }
}

impl Default for AutomationEngine {
    fn default() -> Self {
        Self::new(48000.0)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION PROCESSOR (for audio thread)
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-computed automation data for a block
pub struct AutomationBlock {
    /// Param changes at sample offsets
    pub changes: Vec<(usize, f64)>,
}

impl AutomationBlock {
    /// Get value at sample offset using linear interpolation
    pub fn value_at(&self, offset: usize) -> f64 {
        if self.changes.is_empty() {
            return 0.5; // Default
        }

        if offset <= self.changes[0].0 {
            return self.changes[0].1;
        }

        if offset >= self.changes.last().unwrap().0 {
            return self.changes.last().unwrap().1;
        }

        // Find surrounding points and interpolate
        for i in 1..self.changes.len() {
            if self.changes[i].0 >= offset {
                let (t1, v1) = self.changes[i - 1];
                let (t2, v2) = self.changes[i];
                let t = (offset - t1) as f64 / (t2 - t1) as f64;
                return v1 + (v2 - v1) * t;
            }
        }

        self.changes.last().unwrap().1
    }

    /// Apply automation to a value buffer
    pub fn apply_to_buffer(&self, buffer: &mut [f64], base_value: f64) {
        for (i, sample) in buffer.iter_mut().enumerate() {
            let auto_value = self.value_at(i);
            *sample = base_value * auto_value;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_automation_point() {
        let point = AutomationPoint::new(48000, 0.5);
        assert_eq!(point.time_samples, 48000);
        assert_eq!(point.value, 0.5);
        assert_eq!(point.curve, CurveType::Linear);
    }

    #[test]
    fn test_automation_lane() {
        let param_id = ParamId::track_volume(1);
        let mut lane = AutomationLane::new(param_id, "Volume");

        // Add some points
        lane.add_point(AutomationPoint::new(0, 0.0));
        lane.add_point(AutomationPoint::new(48000, 1.0));
        lane.add_point(AutomationPoint::new(96000, 0.5));

        // Test interpolation
        assert!((lane.value_at(0) - 0.0).abs() < 0.001);
        assert!((lane.value_at(24000) - 0.5).abs() < 0.001);
        assert!((lane.value_at(48000) - 1.0).abs() < 0.001);
        assert!((lane.value_at(72000) - 0.75).abs() < 0.001);
        assert!((lane.value_at(96000) - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_automation_lane_step() {
        let param_id = ParamId::track_mute(1);
        let mut lane = AutomationLane::new(param_id, "Mute");

        lane.add_point(AutomationPoint::new(0, 0.0).with_curve(CurveType::Step));
        lane.add_point(AutomationPoint::new(48000, 1.0).with_curve(CurveType::Step));

        // Step should hold value until next point
        assert!((lane.value_at(24000) - 0.0).abs() < 0.001);
        assert!((lane.value_at(47999) - 0.0).abs() < 0.001);
        assert!((lane.value_at(48000) - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_automation_engine() {
        let engine = AutomationEngine::new(48000.0);

        let param_id = ParamId::track_volume(1);
        engine.get_or_create_lane(param_id.clone(), "Volume");

        engine.add_point(&param_id, AutomationPoint::new(0, 0.0));
        engine.add_point(&param_id, AutomationPoint::new(48000, 1.0));

        engine.set_position(24000);
        let value = engine.get_value(&param_id);
        assert!(value.is_some());
        assert!((value.unwrap() - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_automation_modes() {
        let engine = AutomationEngine::new(48000.0);

        engine.set_mode(AutomationMode::Read);
        assert_eq!(engine.mode(), AutomationMode::Read);

        let param_id = ParamId::track_pan(1);
        engine.set_param_mode(param_id.clone(), AutomationMode::Touch);
        assert_eq!(engine.param_mode(&param_id), AutomationMode::Touch);
    }

    #[test]
    fn test_automation_block() {
        let block = AutomationBlock {
            changes: vec![(0, 0.0), (512, 1.0)],
        };

        assert!((block.value_at(0) - 0.0).abs() < 0.001);
        assert!((block.value_at(256) - 0.5).abs() < 0.001);
        assert!((block.value_at(512) - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_bezier_interpolation() {
        let param_id = ParamId::track_volume(1);
        let mut lane = AutomationLane::new(param_id, "Volume");

        lane.add_point(
            AutomationPoint::new(0, 0.0)
                .with_bezier((0.25, 0.1), (0.75, 0.9))
        );
        lane.add_point(AutomationPoint::new(48000, 1.0));

        // Value at midpoint should be influenced by bezier curve
        let mid_value = lane.value_at(24000);
        // With S-shaped bezier, midpoint should be around 0.5
        assert!(mid_value > 0.4 && mid_value < 0.6);
    }
}
