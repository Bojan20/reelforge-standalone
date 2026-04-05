//! Automation Engine
//!
//! Sample-accurate parameter automation system:
//! - Bezier curve interpolation
//! - Touch/Latch/Write modes
//! - Automation lanes per parameter
//! - Real-time recording and playback

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
        let idx = self
            .points
            .binary_search_by_key(&point.time_samples, |p| p.time_samples)
            .unwrap_or_else(|i| i);
        self.points.insert(idx, point);
    }

    /// Remove point at time (within tolerance)
    pub fn remove_point_at(&mut self, time_samples: u64, tolerance: u64) -> bool {
        if let Some(idx) = self
            .points
            .iter()
            .position(|p| (p.time_samples as i64 - time_samples as i64).abs() <= tolerance as i64)
        {
            self.points.remove(idx);
            true
        } else {
            false
        }
    }

    /// Get mutable access to all points
    pub fn points_mut(&mut self) -> &mut Vec<AutomationPoint> {
        &mut self.points
    }

    /// Get all points within sample range (for sample-accurate automation)
    pub fn points_in_range(
        &self,
        start_sample: u64,
        end_sample: u64,
    ) -> impl Iterator<Item = &AutomationPoint> {
        self.points
            .iter()
            .filter(move |p| p.time_samples >= start_sample && p.time_samples < end_sample)
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

        // After last point (SAFETY: is_empty() check above guarantees last() is Some)
        let last = self.points.last().expect("points checked non-empty above");
        if time_samples >= last.time_samples {
            return last.value;
        }

        // Find surrounding points
        let idx = self
            .points
            .binary_search_by_key(&time_samples, |p| p.time_samples)
            .unwrap_or_else(|i| i);

        if idx == 0 {
            return self.points[0].value;
        }

        let p1 = &self.points[idx - 1];
        let p2 = &self.points[idx];

        // Interpolation factor
        let t =
            (time_samples - p1.time_samples) as f64 / (p2.time_samples - p1.time_samples) as f64;

        self.interpolate(p1, p2, t)
    }

    /// Interpolate between two points
    fn interpolate(&self, p1: &AutomationPoint, p2: &AutomationPoint, t: f64) -> f64 {
        match p1.curve {
            CurveType::Linear => p1.value + (p2.value - p1.value) * t,
            CurveType::Step => p1.value,
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
            CurveType::Bezier => self.bezier_interpolate(p1, p2, t),
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

/// Automation change within a block (for sample-accurate processing)
#[derive(Debug, Clone)]
pub struct AutomationChange {
    /// Sample offset within block (0 = start of block)
    pub sample_offset: usize,
    /// Parameter ID
    pub param_id: ParamId,
    /// Normalized value (0.0 - 1.0)
    pub value: f64,
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
        self.param_modes
            .read()
            .get(param_id)
            .copied()
            .unwrap_or_else(|| *self.mode.read())
    }

    /// Add or get automation lane
    pub fn get_or_create_lane(&self, param_id: ParamId, name: &str) -> ParamId {
        let mut lanes = self.lanes.write();
        if !lanes.contains_key(&param_id) {
            lanes.insert(
                param_id.clone(),
                AutomationLane::new(param_id.clone(), name),
            );
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

    /// Modify lane, creating it if it doesn't exist
    pub fn with_lane_or_create<F, R>(&self, param_id: &ParamId, name: &str, f: F) -> R
    where
        F: FnOnce(&mut AutomationLane) -> R,
    {
        let mut lanes = self.lanes.write();
        let lane = lanes
            .entry(param_id.clone())
            .or_insert_with(|| AutomationLane::new(param_id.clone(), name));
        f(lane)
    }

    /// Add point to lane
    pub fn add_point(&self, param_id: &ParamId, point: AutomationPoint) {
        if let Some(lane) = self.lanes.write().get_mut(param_id) {
            lane.add_point(point);
        }
    }

    /// Set playback position
    pub fn set_position(&self, samples: u64) {
        self.position
            .store(samples, std::sync::atomic::Ordering::Relaxed);
    }

    /// Get current position
    pub fn position(&self) -> u64 {
        self.position.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Advance position by sample count
    pub fn advance(&self, samples: u64) {
        self.position
            .fetch_add(samples, std::sync::atomic::Ordering::Relaxed);
    }

    /// Set playing state
    pub fn set_playing(&self, playing: bool) {
        self.is_playing
            .store(playing, std::sync::atomic::Ordering::Relaxed);
    }

    /// Is playing
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Set recording state
    pub fn set_recording(&self, recording: bool) {
        self.is_recording
            .store(recording, std::sync::atomic::Ordering::Relaxed);
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
        if matches!(
            mode,
            AutomationMode::Touch | AutomationMode::Latch | AutomationMode::Write
        ) && self.touched_params.read().contains_key(param_id)
        {
            return None;
        }

        // Read automation
        let lanes = self.lanes.read();
        if let Some(lane) = lanes.get(param_id)
            && lane.enabled
            && !lane.points.is_empty()
        {
            let pos = self.position();
            return Some(lane.value_at(pos));
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
        if let Some(lane) = lanes.get(param_id)
            && lane.enabled
            && !lane.points.is_empty()
        {
            return Some(lane.value_at(time_samples));
        }

        None
    }

    /// Get interpolated values for a block of samples
    /// Returns Vec of (sample_offset, value) pairs where value changes
    pub fn get_block_values(
        &self,
        param_id: &ParamId,
        start: u64,
        block_size: usize,
    ) -> Vec<(usize, f64)> {
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

        if matches!(
            mode,
            AutomationMode::Touch
                | AutomationMode::Latch
                | AutomationMode::Write
                | AutomationMode::Trim
        ) {
            self.touched_params
                .write()
                .insert(param_id.clone(), current_value);
        }

        // For Trim mode, also record the original automation value and position
        if mode == AutomationMode::Trim {
            let pos = self.position();
            let original = self
                .lanes
                .read()
                .get(&param_id)
                .map(|l| l.value_at(pos))
                .unwrap_or(current_value);

            self.trim_info.write().insert(
                param_id,
                TrimInfo {
                    original_value: original,
                    start_pos: pos,
                    delta: 0.0,
                },
            );
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
        let changes: Vec<_> = pending
            .drain(..)
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

    // ═══════════════════════════════════════════════════════════════════════
    // SAMPLE-ACCURATE BLOCK PROCESSING (Lock-Free for Audio Thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get all automation changes within a block for ALL parameters
    /// Returns changes sorted by sample offset for sample-accurate processing
    /// Uses try_read() for lock-free access - skips automation if lock contended
    pub fn get_all_block_changes(
        &self,
        start_sample: u64,
        block_size: usize,
    ) -> Vec<AutomationChange> {
        // Lock-free read - skip if contended
        let lanes = match self.lanes.try_read() {
            Some(l) => l,
            None => return Vec::new(),
        };

        let end_sample = start_sample + block_size as u64;
        let mut all_changes = Vec::with_capacity(32);

        for (param_id, lane) in lanes.iter() {
            if !lane.enabled || lane.points.is_empty() {
                continue;
            }

            // Get value at block start
            let start_value = lane.value_at(start_sample);
            all_changes.push(AutomationChange {
                sample_offset: 0,
                param_id: param_id.clone(),
                value: start_value,
            });

            // Find all points within block
            for point in lane.points.iter() {
                if point.time_samples > start_sample && point.time_samples < end_sample {
                    all_changes.push(AutomationChange {
                        sample_offset: (point.time_samples - start_sample) as usize,
                        param_id: param_id.clone(),
                        value: point.value,
                    });
                }
            }
        }

        // Sort by sample offset for sequential processing
        all_changes.sort_by_key(|c| c.sample_offset);
        all_changes
    }

    /// Get automation changes for a specific parameter in a block
    /// Returns None if no changes in block
    pub fn get_param_block_changes(
        &self,
        param_id: &ParamId,
        start_sample: u64,
        block_size: usize,
    ) -> Option<Vec<AutomationChange>> {
        let lanes = self.lanes.try_read()?;
        let lane = lanes.get(param_id)?;

        if !lane.enabled || lane.points.is_empty() {
            return None;
        }

        let end_sample = start_sample + block_size as u64;
        let mut changes = Vec::with_capacity(8);

        // Start value
        changes.push(AutomationChange {
            sample_offset: 0,
            param_id: param_id.clone(),
            value: lane.value_at(start_sample),
        });

        // Points within block
        for point in lane.points.iter() {
            if point.time_samples > start_sample && point.time_samples < end_sample {
                changes.push(AutomationChange {
                    sample_offset: (point.time_samples - start_sample) as usize,
                    param_id: param_id.clone(),
                    value: point.value,
                });
            }
        }

        if changes.len() <= 1 {
            // Only start value, no changes within block
            return None;
        }

        Some(changes)
    }

    /// Process block with sample-accurate automation
    /// Callback is called for each sub-block with constant automation value
    /// Returns number of sub-blocks processed
    pub fn process_block_with_automation<F>(
        &self,
        param_id: &ParamId,
        start_sample: u64,
        block_size: usize,
        mut process_fn: F,
    ) -> usize
    where
        F: FnMut(usize, usize, f64), // (start_offset, length, value)
    {
        let changes = match self.get_param_block_changes(param_id, start_sample, block_size) {
            Some(c) if c.len() > 1 => c,
            _ => {
                // No automation, process whole block
                let value = self.get_value_at(param_id, start_sample).unwrap_or(0.5);
                process_fn(0, block_size, value);
                return 1;
            }
        };

        let mut offset = 0;
        let mut sub_blocks = 0;

        for i in 0..changes.len() {
            let current = &changes[i];
            let next_offset = if i + 1 < changes.len() {
                changes[i + 1].sample_offset
            } else {
                block_size
            };

            if next_offset > offset {
                process_fn(offset, next_offset - offset, current.value);
                offset = next_offset;
                sub_blocks += 1;
            }
        }

        sub_blocks
    }

    /// Get interpolated value at any sample within a block
    /// Useful for per-sample automation (expensive, use sparingly)
    pub fn get_interpolated_value(&self, param_id: &ParamId, sample: u64) -> Option<f64> {
        let lanes = self.lanes.try_read()?;
        let lane = lanes.get(param_id)?;

        if !lane.enabled {
            return None;
        }

        Some(lane.value_at(sample))
    }
}

impl Default for AutomationEngine {
    fn default() -> Self {
        Self::new(48000.0)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION ITEMS — Reaper-style containerized automation
// ═══════════════════════════════════════════════════════════════════════════
//
// Automation Items are clips of automation placed ON an automation lane.
// They are the equivalent of audio clips on a track, but for automation data.
//
// Key concepts:
// - **Pooling:** Multiple items can share one pool entry. Edit one → all update.
// - **Looping:** Item content repeats within the item's time range.
// - **Stacking:** Overlapping items combine additively (sum of offsets from baseline).
// - **LFO Shapes:** Built-in generators (sine, triangle, square, saw, random, S&H).
// - **Stretch:** Changing item length stretches the contained automation proportionally.
// - **Baseline/Amplitude:** Each item has baseline (center value) and amplitude (depth).

use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};

/// Unique automation item identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AutomationItemId(pub u64);

/// Pool identifier — items sharing a pool are edited together
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AutomationPoolId(pub u64);

static NEXT_AUTO_ITEM_ID: AtomicU64 = AtomicU64::new(1);
static NEXT_POOL_ID: AtomicU64 = AtomicU64::new(1);

fn next_auto_item_id() -> AutomationItemId {
    AutomationItemId(NEXT_AUTO_ITEM_ID.fetch_add(1, AtomicOrdering::Relaxed))
}

fn next_pool_id() -> AutomationPoolId {
    AutomationPoolId(NEXT_POOL_ID.fetch_add(1, AtomicOrdering::Relaxed))
}

/// Built-in LFO waveform shapes
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub enum LfoShape {
    /// Sine wave (smooth oscillation)
    #[default]
    Sine,
    /// Triangle wave (linear ramp up/down)
    Triangle,
    /// Square wave (instant on/off)
    Square,
    /// Sawtooth (linear ramp up, instant drop)
    SawUp,
    /// Reverse sawtooth (instant rise, linear ramp down)
    SawDown,
    /// Random (new random value each cycle)
    Random,
    /// Sample & Hold (random value, held for period)
    SampleAndHold,
}

impl LfoShape {
    /// Evaluate LFO at normalized phase (0.0 - 1.0).
    /// Returns value in range -1.0 to 1.0.
    #[inline]
    pub fn evaluate(&self, phase: f64) -> f64 {
        match self {
            LfoShape::Sine => (phase * std::f64::consts::TAU).sin(),
            LfoShape::Triangle => {
                if phase < 0.25 {
                    phase * 4.0
                } else if phase < 0.75 {
                    2.0 - phase * 4.0
                } else {
                    phase * 4.0 - 4.0
                }
            }
            LfoShape::Square => {
                if phase < 0.5 { 1.0 } else { -1.0 }
            }
            LfoShape::SawUp => phase * 2.0 - 1.0,
            LfoShape::SawDown => 1.0 - phase * 2.0,
            LfoShape::Random | LfoShape::SampleAndHold => {
                // Deterministic pseudo-random based on phase quantization.
                // For S&H, caller should quantize phase to steps.
                // For Random, each sample gets a unique value.
                let seed = (phase * 1000000.0) as u64;
                let hash = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                ((hash >> 33) as f64 / (u32::MAX as f64)) * 2.0 - 1.0
            }
        }
    }
}

/// Shape source for an automation item: custom points or generated LFO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AutomationItemShape {
    /// Custom user-drawn automation curve (relative time 0.0-1.0, value 0.0-1.0)
    Custom {
        /// Points in normalized space: time 0.0-1.0, value 0.0-1.0
        points: Vec<AutomationPoint>,
    },
    /// Built-in LFO generator
    Lfo {
        /// Waveform shape
        shape: LfoShape,
        /// Frequency in Hz (cycles per second of real time)
        frequency: f64,
        /// Phase offset (0.0-1.0)
        phase_offset: f64,
        /// Pulse width for square wave (0.0-1.0, 0.5 = symmetric)
        pulse_width: f64,
        /// Attack/release smoothing in seconds (0 = instant)
        smoothing: f64,
    },
}

impl Default for AutomationItemShape {
    fn default() -> Self {
        Self::Lfo {
            shape: LfoShape::Sine,
            frequency: 1.0,
            phase_offset: 0.0,
            pulse_width: 0.5,
            smoothing: 0.0,
        }
    }
}

/// A single automation item placed on an automation lane.
///
/// Think of it as a "clip" of automation. Has position, length, and content.
/// Content can be custom points or an LFO generator.
///
/// ## Stacking
/// When multiple items overlap on the same lane, their outputs are **additively combined**:
/// `final_value = lane_base + sum_of_item_offsets`
///
/// Each item produces an offset from its baseline:
/// `item_offset = (shape_value - 0.5) * 2.0 * amplitude`
///
/// Where `shape_value` is 0.0-1.0 (from custom points or LFO mapped to 0-1 range).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationItem {
    /// Unique ID
    pub id: AutomationItemId,
    /// Pool this item belongs to (for shared editing). None = standalone.
    pub pool_id: Option<AutomationPoolId>,
    /// Start position on the automation lane (in samples, absolute timeline)
    pub start_samples: u64,
    /// Length of the item (in samples)
    pub length_samples: u64,
    /// Loop the item content within its length
    pub looping: bool,
    /// Number of loops (0 = fill entire length)
    pub loop_count: u32,
    /// Baseline value (center, 0.0-1.0). Item oscillates around this.
    pub baseline: f64,
    /// Amplitude/depth (0.0-1.0). How far from baseline the shape can reach.
    pub amplitude: f64,
    /// Shape source: custom points or LFO
    pub shape: AutomationItemShape,
    /// Is this item enabled
    pub enabled: bool,
    /// Is this item muted (still visible but not applied)
    pub muted: bool,
    /// Playback rate multiplier (1.0 = normal, 2.0 = double speed)
    pub rate: f64,
    /// Time stretch mode: if true, changing length stretches content; if false, reveals more.
    pub stretch_with_length: bool,
}

impl AutomationItem {
    /// Create a new automation item with LFO shape
    pub fn new_lfo(
        start_samples: u64,
        length_samples: u64,
        shape: LfoShape,
        frequency: f64,
    ) -> Self {
        Self {
            id: next_auto_item_id(),
            pool_id: None,
            start_samples,
            length_samples,
            looping: true,
            loop_count: 0,
            baseline: 0.5,
            amplitude: 0.5,
            shape: AutomationItemShape::Lfo {
                shape,
                frequency,
                phase_offset: 0.0,
                pulse_width: 0.5,
                smoothing: 0.0,
            },
            enabled: true,
            muted: false,
            rate: 1.0,
            stretch_with_length: true,
        }
    }

    /// Create a new automation item with custom points
    pub fn new_custom(start_samples: u64, length_samples: u64) -> Self {
        Self {
            id: next_auto_item_id(),
            pool_id: None,
            start_samples,
            length_samples,
            looping: false,
            loop_count: 0,
            baseline: 0.5,
            amplitude: 1.0,
            shape: AutomationItemShape::Custom {
                points: vec![
                    AutomationPoint::new(0, 0.5),    // Start at center
                    AutomationPoint::new(1000, 0.5),  // End at center (will be stretched)
                ],
            },
            enabled: true,
            muted: false,
            rate: 1.0,
            stretch_with_length: true,
        }
    }

    /// End position (in samples)
    #[inline]
    pub fn end_samples(&self) -> u64 {
        self.start_samples + self.length_samples
    }

    /// Check if sample position is within this item
    #[inline]
    pub fn contains(&self, sample: u64) -> bool {
        sample >= self.start_samples && sample < self.end_samples()
    }

    /// Evaluate the automation item at an absolute sample position.
    /// Returns the offset from baseline (can be negative or positive).
    /// Range: -amplitude to +amplitude.
    ///
    /// Zero allocations — all stack operations.
    pub fn value_offset_at(&self, sample: u64, sample_rate: f64) -> f64 {
        self.value_offset_at_with_shape(&self.shape, sample, sample_rate)
    }

    /// Evaluate with an external shape reference (used for pooled items to avoid cloning).
    /// Zero allocations — all stack operations.
    pub fn value_offset_at_with_shape(
        &self,
        shape: &AutomationItemShape,
        sample: u64,
        sample_rate: f64,
    ) -> f64 {
        if !self.enabled || self.muted || !self.contains(sample) {
            return 0.0;
        }

        let relative = (sample - self.start_samples) as f64 * self.rate;
        let content_len = match shape {
            AutomationItemShape::Lfo { frequency, .. } => {
                if *frequency > 0.0 {
                    sample_rate / frequency
                } else {
                    self.length_samples as f64
                }
            }
            AutomationItemShape::Custom { points } => {
                points.last().map(|p| p.time_samples as f64).unwrap_or(1000.0)
            }
        };

        if content_len <= 0.0 {
            return 0.0;
        }

        // Compute phase within content
        let phase = if self.looping {
            if self.loop_count > 0 {
                let iteration = (relative / content_len) as u32;
                if iteration >= self.loop_count {
                    return 0.0; // Past loop count
                }
            }
            (relative % content_len) / content_len
        } else if self.stretch_with_length {
            // Stretch mode: map item length to content 0-1
            relative / (self.length_samples as f64)
        } else {
            // Reveal mode: show more content as item gets longer
            relative / content_len
        };

        let phase = phase.clamp(0.0, 1.0);

        // Evaluate shape at this phase
        let shape_value = match shape {
            AutomationItemShape::Lfo {
                shape: lfo_shape,
                phase_offset,
                pulse_width,
                ..
            } => {
                let effective_phase = (phase + phase_offset) % 1.0;
                let raw = match lfo_shape {
                    LfoShape::Square => {
                        // Use pulse width for duty cycle
                        if effective_phase < *pulse_width { 1.0 } else { -1.0 }
                    }
                    LfoShape::SampleAndHold => {
                        // Quantize phase to fixed steps for S&H behavior
                        let steps = (self.length_samples as f64 / content_len).max(1.0) * 16.0;
                        let quantized = (effective_phase * steps).floor() / steps;
                        lfo_shape.evaluate(quantized)
                    }
                    _ => lfo_shape.evaluate(effective_phase),
                };
                // Map -1..1 to 0..1
                (raw + 1.0) * 0.5
            }
            AutomationItemShape::Custom { points } => {
                // Evaluate custom curve at phase position
                if points.is_empty() {
                    0.5
                } else {
                    // Map phase to custom points' time range
                    let max_time = points.last().map(|p| p.time_samples).unwrap_or(1000);
                    let time_at = (phase * max_time as f64) as u64;

                    // Binary search interpolation (reuse AutomationLane logic inline)
                    if time_at <= points[0].time_samples {
                        points[0].value
                    } else if time_at >= max_time {
                        points.last().map(|p| p.value).unwrap_or(0.5)
                    } else {
                        let idx = points
                            .binary_search_by_key(&time_at, |p| p.time_samples)
                            .unwrap_or_else(|i| i);
                        if idx == 0 {
                            points[0].value
                        } else {
                            let p1 = &points[idx - 1];
                            let p2 = &points[idx.min(points.len() - 1)];
                            let span = p2.time_samples.saturating_sub(p1.time_samples);
                            if span == 0 {
                                p1.value
                            } else {
                                let t = (time_at - p1.time_samples) as f64 / span as f64;
                                // Use curve type from p1
                                match p1.curve {
                                    CurveType::Linear => p1.value + (p2.value - p1.value) * t,
                                    CurveType::Step => p1.value,
                                    CurveType::Exponential => p1.value + (p2.value - p1.value) * t * t,
                                    CurveType::Logarithmic => p1.value + (p2.value - p1.value) * t.sqrt(),
                                    CurveType::SCurve => {
                                        let s = t * t * (3.0 - 2.0 * t);
                                        p1.value + (p2.value - p1.value) * s
                                    }
                                    CurveType::Bezier => {
                                        let cp1 = p1.bezier_cp1.unwrap_or((0.33, 0.0));
                                        let cp2 = p1.bezier_cp2.unwrap_or((0.66, 0.0));
                                        let y0 = p1.value;
                                        let y3 = p2.value;
                                        let y1 = y0 + cp1.1 * (y3 - y0);
                                        let y2 = y0 + cp2.1 * (y3 - y0);
                                        let t2 = t * t;
                                        let t3 = t2 * t;
                                        let mt = 1.0 - t;
                                        let mt2 = mt * mt;
                                        let mt3 = mt2 * mt;
                                        mt3 * y0 + 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3 * y3
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };

        // Convert shape_value (0-1) to offset from lane center (0.5).
        // Item oscillates around its baseline with given amplitude:
        //   output = baseline + (shape - 0.5) * 2 * amplitude
        //   offset = output - 0.5 (since 0.5 is the neutral lane value)
        (self.baseline - 0.5) + (shape_value - 0.5) * 2.0 * self.amplitude
    }
}

/// Pool entry: shared automation data that multiple items reference.
/// Edit the pool → all items using this pool see the change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationPool {
    pub id: AutomationPoolId,
    pub name: String,
    /// The shared shape data
    pub shape: AutomationItemShape,
    /// How many items reference this pool
    pub ref_count: u32,
}

impl AutomationPool {
    pub fn new(name: &str, shape: AutomationItemShape) -> Self {
        Self {
            id: next_pool_id(),
            name: name.to_string(),
            shape,
            ref_count: 0,
        }
    }
}

/// Manages all automation items across all lanes.
///
/// Items live on `AutomationLane`s (identified by `ParamId`).
/// Multiple items can stack on the same lane — their offsets are summed.
///
/// ## Evaluation Order
/// 1. Base lane value from `AutomationEngine` (the underlying automation curve)
/// 2. Sum of all active item offsets at that sample position
/// 3. Clamp to lane's min/max range
pub struct AutomationItemManager {
    /// Items grouped by the lane they're on
    items: RwLock<HashMap<ParamId, Vec<AutomationItem>>>,
    /// Shared pools for pooled editing
    pools: RwLock<HashMap<AutomationPoolId, AutomationPool>>,
    /// Sample rate for LFO frequency calculations
    sample_rate: f64,
}

impl AutomationItemManager {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            items: RwLock::new(HashMap::new()),
            pools: RwLock::new(HashMap::new()),
            sample_rate,
        }
    }

    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    // ═══════════════════════════════════════════════════════
    // ITEM CRUD
    // ═══════════════════════════════════════════════════════

    /// Add an automation item to a lane
    pub fn add_item(&self, param_id: &ParamId, item: AutomationItem) -> AutomationItemId {
        let id = item.id;
        self.items
            .write()
            .entry(param_id.clone())
            .or_default()
            .push(item);
        id
    }

    /// Remove an automation item
    pub fn remove_item(&self, param_id: &ParamId, item_id: AutomationItemId) -> bool {
        // Extract pool_id while holding items lock, then release before touching pools
        let pool_id = {
            let mut items = self.items.write();
            if let Some(lane_items) = items.get_mut(param_id) {
                if let Some(idx) = lane_items.iter().position(|i| i.id == item_id) {
                    let item = lane_items.remove(idx);
                    item.pool_id
                } else {
                    return false;
                }
            } else {
                return false;
            }
        };
        // Decrement pool ref count (items lock released)
        if let Some(pid) = pool_id
            && let Some(pool) = self.pools.write().get_mut(&pid) {
                pool.ref_count = pool.ref_count.saturating_sub(1);
            }
        true
    }

    /// Get item by ID
    pub fn get_item(&self, param_id: &ParamId, item_id: AutomationItemId) -> Option<AutomationItem> {
        self.items
            .read()
            .get(param_id)?
            .iter()
            .find(|i| i.id == item_id)
            .cloned()
    }

    /// Get all items on a lane
    pub fn get_lane_items(&self, param_id: &ParamId) -> Vec<AutomationItem> {
        self.items
            .read()
            .get(param_id)
            .cloned()
            .unwrap_or_default()
    }

    /// Modify an item in place
    pub fn with_item<F, R>(&self, param_id: &ParamId, item_id: AutomationItemId, f: F) -> Option<R>
    where
        F: FnOnce(&mut AutomationItem) -> R,
    {
        let mut items = self.items.write();
        items.get_mut(param_id)?.iter_mut().find(|i| i.id == item_id).map(f)
    }

    /// Duplicate an item (creates a new ID, optionally at a new position)
    pub fn duplicate_item(
        &self,
        param_id: &ParamId,
        item_id: AutomationItemId,
        new_start: Option<u64>,
    ) -> Option<AutomationItemId> {
        let item = self.get_item(param_id, item_id)?;
        let mut new_item = item.clone();
        new_item.id = next_auto_item_id();
        if let Some(start) = new_start {
            new_item.start_samples = start;
        } else {
            // Place right after original
            new_item.start_samples = item.end_samples();
        }
        // If pooled, increment ref count
        if let Some(pool_id) = new_item.pool_id
            && let Some(pool) = self.pools.write().get_mut(&pool_id) {
                pool.ref_count += 1;
            }
        let id = self.add_item(param_id, new_item);
        Some(id)
    }

    /// Move an item (change start position)
    pub fn move_item(&self, param_id: &ParamId, item_id: AutomationItemId, new_start: u64) {
        self.with_item(param_id, item_id, |item| {
            item.start_samples = new_start;
        });
    }

    /// Resize an item (change length)
    pub fn resize_item(&self, param_id: &ParamId, item_id: AutomationItemId, new_length: u64) {
        self.with_item(param_id, item_id, |item| {
            item.length_samples = new_length.max(1);
        });
    }

    // ═══════════════════════════════════════════════════════
    // POOLING
    // ═══════════════════════════════════════════════════════

    /// Create a pool from an item's shape. The item and all future copies share this pool.
    pub fn pool_item(&self, param_id: &ParamId, item_id: AutomationItemId) -> Option<AutomationPoolId> {
        // Phase 1: Update item under items lock, extract shape for pool creation
        let (pool_shape, pool_id_result) = {
            let mut items = self.items.write();
            let lane_items = items.get_mut(param_id)?;
            let item = lane_items.iter_mut().find(|i| i.id == item_id)?;

            // Already pooled?
            if let Some(pid) = item.pool_id {
                return Some(pid);
            }

            // Pre-generate pool ID and set it on the item
            let pool_id = next_pool_id();
            let shape = item.shape.clone();
            item.pool_id = Some(pool_id);
            (shape, pool_id)
        };
        // Phase 2: Create pool entry (items lock released)
        let mut pool = AutomationPool::new("Pool", pool_shape);
        pool.id = pool_id_result;
        pool.ref_count = 1;
        self.pools.write().insert(pool_id_result, pool);

        Some(pool_id_result)
    }

    /// Unpool an item (detach from pool, becomes standalone with a copy of the shape)
    pub fn unpool_item(&self, param_id: &ParamId, item_id: AutomationItemId) {
        // Phase 1: Get pool shape copy and detach item from pool
        let pool_id = {
            let mut items = self.items.write();
            if let Some(lane_items) = items.get_mut(param_id) {
                if let Some(item) = lane_items.iter_mut().find(|i| i.id == item_id) {
                    if let Some(pid) = item.pool_id.take() {
                        // Copy pool shape to item before detaching
                        if let Some(pool) = self.pools.read().get(&pid) {
                            item.shape = pool.shape.clone();
                        }
                        Some(pid)
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            }
        };
        // Phase 2: Decrement pool ref count (items lock released)
        if let Some(pid) = pool_id {
            let mut pools = self.pools.write();
            if let Some(pool) = pools.get_mut(&pid) {
                pool.ref_count = pool.ref_count.saturating_sub(1);
                if pool.ref_count == 0 {
                    pools.remove(&pid);
                }
            }
        }
    }

    /// Edit a pool's shape. All items referencing this pool will see the change.
    pub fn edit_pool_shape(&self, pool_id: AutomationPoolId, shape: AutomationItemShape) {
        if let Some(pool) = self.pools.write().get_mut(&pool_id) {
            pool.shape = shape;
        }
    }

    /// Get pool by ID
    pub fn get_pool(&self, pool_id: AutomationPoolId) -> Option<AutomationPool> {
        self.pools.read().get(&pool_id).cloned()
    }

    /// Get all pools
    pub fn get_pools(&self) -> Vec<AutomationPool> {
        self.pools.read().values().cloned().collect()
    }

    // ═══════════════════════════════════════════════════════
    // EVALUATION (Audio Thread Safe)
    // ═══════════════════════════════════════════════════════

    /// Get the combined offset from all automation items at a sample position.
    ///
    /// Items stack additively: `total_offset = sum(item.value_offset_at(sample))`.
    /// For pooled items, the pool's shape is used instead of the item's local shape.
    ///
    /// Returns 0.0 if no items affect this position.
    ///
    /// Lock-free: uses `try_read()` to avoid blocking the audio thread.
    #[inline]
    pub fn combined_offset_at(&self, param_id: &ParamId, sample: u64) -> f64 {
        let items = match self.items.try_read() {
            Some(i) => i,
            None => return 0.0,
        };

        let lane_items = match items.get(param_id) {
            Some(li) => li,
            None => return 0.0,
        };

        let pools = self.pools.try_read();
        let mut total_offset = 0.0;

        for item in lane_items {
            if !item.enabled || item.muted || !item.contains(sample) {
                continue;
            }

            // If pooled, use pool shape reference (zero alloc); otherwise use item's own
            if let Some(pool_id) = item.pool_id
                && let Some(ref pools_guard) = pools
                    && let Some(pool) = pools_guard.get(&pool_id) {
                        total_offset += item.value_offset_at_with_shape(
                            &pool.shape, sample, self.sample_rate,
                        );
                        continue;
                    }
            total_offset += item.value_offset_at(sample, self.sample_rate);
        }

        total_offset
    }

    /// Evaluate final value: base lane value + stacked item offsets, clamped to 0-1.
    #[inline]
    pub fn evaluate_at(&self, param_id: &ParamId, base_value: f64, sample: u64) -> f64 {
        let offset = self.combined_offset_at(param_id, sample);
        (base_value + offset).clamp(0.0, 1.0)
    }

    /// Get items that overlap with a time range (for UI rendering)
    pub fn items_in_range(
        &self,
        param_id: &ParamId,
        start: u64,
        end: u64,
    ) -> Vec<AutomationItem> {
        self.items
            .read()
            .get(param_id)
            .map(|items| {
                items
                    .iter()
                    .filter(|i| i.start_samples < end && i.end_samples() > start)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Clear all items on a lane
    pub fn clear_lane(&self, param_id: &ParamId) {
        // Phase 1: Remove items, collect pool IDs (items lock scoped)
        let pool_ids: Vec<AutomationPoolId> = {
            self.items
                .write()
                .remove(param_id)
                .unwrap_or_default()
                .into_iter()
                .filter_map(|i| i.pool_id)
                .collect()
        };
        // Phase 2: Decrement pool ref counts (items lock released)
        if !pool_ids.is_empty() {
            let mut pools = self.pools.write();
            for pool_id in pool_ids {
                if let Some(pool) = pools.get_mut(&pool_id) {
                    pool.ref_count = pool.ref_count.saturating_sub(1);
                    if pool.ref_count == 0 {
                        pools.remove(&pool_id);
                    }
                }
            }
        }
    }

    /// Clear everything
    pub fn clear_all(&self) {
        self.items.write().clear();
        self.pools.write().clear();
    }

    /// Get total number of items across all lanes
    pub fn item_count(&self) -> usize {
        self.items.read().values().map(|v| v.len()).sum()
    }

    /// Get total number of pools
    pub fn pool_count(&self) -> usize {
        self.pools.read().len()
    }
}

impl Default for AutomationItemManager {
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

        // SAFETY: is_empty() check above guarantees last() is Some
        let last = self
            .changes
            .last()
            .expect("changes checked non-empty above");

        if offset >= last.0 {
            return last.1;
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

        // Fallback (should never reach here due to bounds check above)
        last.1
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
// SAMPLE-ACCURATE AUTOMATION (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════

impl AutomationEngine {
    /// Get all automation changes within a block (for sample-accurate processing)
    /// Returns changes sorted by sample_offset
    /// Lock-free — uses try_read() to avoid blocking audio thread
    pub fn get_block_changes(&self, start_sample: u64, block_size: usize) -> Vec<AutomationChange> {
        // Try to read lanes without blocking
        let lanes = match self.lanes.try_read() {
            Some(l) => l,
            None => {
                // Lock contention - skip automation this block
                return Vec::new();
            }
        };

        let end_sample = start_sample + block_size as u64;
        let mut changes = Vec::new();

        // Collect all automation points in this block
        for (param_id, lane) in lanes.iter() {
            if !lane.enabled {
                continue;
            }

            for point in lane.points_in_range(start_sample, end_sample) {
                changes.push(AutomationChange {
                    sample_offset: (point.time_samples - start_sample) as usize,
                    param_id: param_id.clone(),
                    value: point.value,
                });
            }
        }

        // Sort by sample offset for sequential application
        changes.sort_by_key(|c| c.sample_offset);
        changes
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

        lane.add_point(AutomationPoint::new(0, 0.0).with_bezier((0.25, 0.1), (0.75, 0.9)));
        lane.add_point(AutomationPoint::new(48000, 1.0));

        // Value at midpoint should be influenced by bezier curve
        let mid_value = lane.value_at(24000);
        // With S-shaped bezier, midpoint should be around 0.5
        assert!(mid_value > 0.4 && mid_value < 0.6);
    }

    // ═══════════════════════════════════════════════════════
    // Automation Item Tests
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_lfo_shapes() {
        // Sine: 0 at phase 0, 1 at phase 0.25, 0 at 0.5, -1 at 0.75
        assert!((LfoShape::Sine.evaluate(0.0)).abs() < 0.01);
        assert!((LfoShape::Sine.evaluate(0.25) - 1.0).abs() < 0.01);
        assert!((LfoShape::Sine.evaluate(0.5)).abs() < 0.01);

        // Triangle: 0 at 0, 1 at 0.25, 0 at 0.5, -1 at 0.75
        assert!((LfoShape::Triangle.evaluate(0.0)).abs() < 0.01);
        assert!((LfoShape::Triangle.evaluate(0.25) - 1.0).abs() < 0.01);
        assert!((LfoShape::Triangle.evaluate(0.5)).abs() < 0.01);

        // Square: 1 for first half, -1 for second half
        assert_eq!(LfoShape::Square.evaluate(0.1), 1.0);
        assert_eq!(LfoShape::Square.evaluate(0.6), -1.0);

        // Saw up: -1 at 0, 1 at 1
        assert!((LfoShape::SawUp.evaluate(0.0) - (-1.0)).abs() < 0.01);
        assert!((LfoShape::SawUp.evaluate(0.5) - 0.0).abs() < 0.01);

        // Saw down: 1 at 0, -1 at 1
        assert!((LfoShape::SawDown.evaluate(0.0) - 1.0).abs() < 0.01);
        assert!((LfoShape::SawDown.evaluate(0.5) - 0.0).abs() < 0.01);
    }

    #[test]
    fn test_automation_item_lfo_basic() {
        let item = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);
        let sr = 48000.0;

        // Item should cover 0..48000
        assert!(item.contains(0));
        assert!(item.contains(47999));
        assert!(!item.contains(48000));

        // At phase 0 (sample 0): sine = 0, mapped to 0.5, offset = 0
        let offset = item.value_offset_at(0, sr);
        assert!(offset.abs() < 0.01, "Expected ~0.0, got {}", offset);

        // At phase 0.25 (quarter): sine = 1.0, mapped to 1.0, offset = (1.0 - 0.5) * 2 * 0.5 = 0.5
        let offset = item.value_offset_at(12000, sr);
        assert!((offset - 0.5).abs() < 0.01, "Expected ~0.5, got {}", offset);
    }

    #[test]
    fn test_automation_item_custom_points() {
        let mut item = AutomationItem::new_custom(0, 48000);
        item.amplitude = 1.0;

        // Set custom points: ramp 0.0 to 1.0 over 1000 time units
        item.shape = AutomationItemShape::Custom {
            points: vec![
                AutomationPoint::new(0, 0.0),
                AutomationPoint::new(1000, 1.0),
            ],
        };

        let sr = 48000.0;
        // At start: value 0.0, offset = (0.0 - 0.5) * 2.0 * 1.0 = -1.0
        let offset = item.value_offset_at(0, sr);
        assert!((offset - (-1.0)).abs() < 0.01, "Expected ~-1.0, got {}", offset);

        // At end: value 1.0, offset = (1.0 - 0.5) * 2.0 * 1.0 = 1.0
        let offset = item.value_offset_at(47999, sr);
        assert!((offset - 1.0).abs() < 0.05, "Expected ~1.0, got {}", offset);
    }

    #[test]
    fn test_automation_item_looping() {
        // LFO at 2 Hz in a 48000-sample (1 sec) item
        let item = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 2.0);
        let sr = 48000.0;

        // One cycle = 24000 samples. At 6000 (quarter of first cycle): peak
        let offset_q1 = item.value_offset_at(6000, sr);
        // At 30000 (quarter of second cycle): should also be peak
        let offset_q2 = item.value_offset_at(30000, sr);

        assert!((offset_q1 - offset_q2).abs() < 0.01,
            "Looping LFO should repeat: {} vs {}", offset_q1, offset_q2);
    }

    #[test]
    fn test_automation_item_stacking() {
        let manager = AutomationItemManager::new(48000.0);
        let param = ParamId::track_volume(1);

        // Two items overlapping: both sine LFOs
        let item1 = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);
        let item2 = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);

        manager.add_item(&param, item1);
        manager.add_item(&param, item2);

        // At quarter point: each contributes ~0.5 offset, stacked = ~1.0
        let combined = manager.combined_offset_at(&param, 12000);
        assert!((combined - 1.0).abs() < 0.05, "Expected ~1.0, got {}", combined);

        // Final value with base 0.5: 0.5 + 1.0 = 1.5, clamped to 1.0
        let final_val = manager.evaluate_at(&param, 0.5, 12000);
        assert!((final_val - 1.0).abs() < 0.01, "Expected 1.0 (clamped), got {}", final_val);
    }

    #[test]
    fn test_automation_item_pooling() {
        let manager = AutomationItemManager::new(48000.0);
        let param = ParamId::track_volume(1);

        // Create item and pool it
        let item = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);
        let item_id = item.id;
        manager.add_item(&param, item);

        let pool_id = manager.pool_item(&param, item_id).unwrap();
        assert_eq!(manager.pool_count(), 1);

        // Duplicate (shares pool)
        let dup_id = manager.duplicate_item(&param, item_id, Some(48000)).unwrap();

        // Pool ref count should be 2
        let pool = manager.get_pool(pool_id).unwrap();
        assert_eq!(pool.ref_count, 2);

        // Edit pool shape → affects both items
        manager.edit_pool_shape(pool_id, AutomationItemShape::Lfo {
            shape: LfoShape::Triangle,
            frequency: 2.0,
            phase_offset: 0.0,
            pulse_width: 0.5,
            smoothing: 0.0,
        });

        // Verify both items now use triangle
        let val1 = manager.combined_offset_at(&param, 6000);  // First item
        let val2 = manager.combined_offset_at(&param, 54000); // Second item (starts at 48000)
        assert!((val1 - val2).abs() < 0.05, "Pooled items should match: {} vs {}", val1, val2);

        // Unpool duplicate
        manager.unpool_item(&param, dup_id);
        let pool = manager.get_pool(pool_id).unwrap();
        assert_eq!(pool.ref_count, 1);
    }

    #[test]
    fn test_automation_item_mute_disable() {
        let manager = AutomationItemManager::new(48000.0);
        let param = ParamId::track_volume(1);

        let mut item = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);
        let item_id = item.id;
        item.muted = true;
        manager.add_item(&param, item);

        // Muted item should contribute 0
        let offset = manager.combined_offset_at(&param, 12000);
        assert!(offset.abs() < 0.001);

        // Unmute
        manager.with_item(&param, item_id, |i| i.muted = false);
        let offset = manager.combined_offset_at(&param, 12000);
        assert!(offset.abs() > 0.1, "Unmuted item should contribute: {}", offset);
    }

    #[test]
    fn test_automation_item_amplitude_baseline() {
        let mut item = AutomationItem::new_lfo(0, 48000, LfoShape::Square, 1.0);
        item.baseline = 0.7;
        item.amplitude = 0.2;

        let sr = 48000.0;
        // New formula: offset = (baseline - 0.5) + (shape - 0.5) * 2.0 * amplitude
        // Square at phase < 0.5: shape_value = 1.0
        // offset = (0.7 - 0.5) + (1.0 - 0.5) * 2.0 * 0.2 = 0.2 + 0.2 = 0.4
        let offset = item.value_offset_at(0, sr);
        assert!((offset - 0.4).abs() < 0.01, "Expected 0.4, got {}", offset);

        // Square at phase > 0.5: shape_value = 0.0
        // offset = (0.7 - 0.5) + (0.0 - 0.5) * 2.0 * 0.2 = 0.2 - 0.2 = 0.0
        let offset = item.value_offset_at(36000, sr);
        assert!(offset.abs() < 0.01, "Expected 0.0, got {}", offset);

        // Baseline at 0.5 should behave like before (no offset from center)
        let mut centered = AutomationItem::new_lfo(0, 48000, LfoShape::Square, 1.0);
        centered.baseline = 0.5;
        centered.amplitude = 0.3;
        let offset_high = centered.value_offset_at(0, sr);
        assert!((offset_high - 0.3).abs() < 0.01, "Expected 0.3, got {}", offset_high);
    }

    #[test]
    fn test_automation_item_manager_crud() {
        let manager = AutomationItemManager::new(48000.0);
        let param = ParamId::track_pan(1);

        assert_eq!(manager.item_count(), 0);

        let item = AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0);
        let item_id = item.id;
        manager.add_item(&param, item);
        assert_eq!(manager.item_count(), 1);

        // Move
        manager.move_item(&param, item_id, 96000);
        let moved = manager.get_item(&param, item_id).unwrap();
        assert_eq!(moved.start_samples, 96000);

        // Resize
        manager.resize_item(&param, item_id, 24000);
        let resized = manager.get_item(&param, item_id).unwrap();
        assert_eq!(resized.length_samples, 24000);

        // Remove
        assert!(manager.remove_item(&param, item_id));
        assert_eq!(manager.item_count(), 0);
    }

    #[test]
    fn test_automation_item_loop_count() {
        let mut item = AutomationItem::new_lfo(0, 96000, LfoShape::Sine, 1.0);
        item.loop_count = 1; // Only 1 loop (content_length = 48000 at 1 Hz)

        let sr = 48000.0;
        // First cycle (0-47999): should produce offsets
        let offset1 = item.value_offset_at(12000, sr);
        assert!(offset1.abs() > 0.1, "First cycle should be active: {}", offset1);

        // Second cycle (48000+): should be 0 (past loop count)
        let offset2 = item.value_offset_at(60000, sr);
        assert!(offset2.abs() < 0.001, "Past loop count should be 0: {}", offset2);
    }

    #[test]
    fn test_automation_items_in_range() {
        let manager = AutomationItemManager::new(48000.0);
        let param = ParamId::track_volume(1);

        manager.add_item(&param, AutomationItem::new_lfo(0, 48000, LfoShape::Sine, 1.0));
        manager.add_item(&param, AutomationItem::new_lfo(96000, 48000, LfoShape::Triangle, 2.0));
        manager.add_item(&param, AutomationItem::new_lfo(200000, 48000, LfoShape::Square, 1.0));

        // Range that covers first two items
        let in_range = manager.items_in_range(&param, 0, 144000);
        assert_eq!(in_range.len(), 2);

        // Range that covers only the last
        let in_range = manager.items_in_range(&param, 200000, 300000);
        assert_eq!(in_range.len(), 1);
    }
}
