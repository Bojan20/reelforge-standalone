//! Comping System
//!
//! Multi-take recording and comping (Cubase/Pro Tools style):
//! - RecordingLane: Vertical lane within a track
//! - Take: Single recording pass with metadata
//! - CompRegion: Selected region from a take for the comp
//!
//! Architecture:
//! Track → RecordingLanes[] → Takes[]
//!                         ↓
//!               CompRegions[] (selections for final comp)

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::TrackId;

// ═══════════════════════════════════════════════════════════════════════════
// IDS
// ═══════════════════════════════════════════════════════════════════════════

/// Lane identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LaneId(pub u64);

/// Take identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TakeId(pub u64);

/// Comp region identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CompRegionId(pub u64);

// ═══════════════════════════════════════════════════════════════════════════
// TAKE RATING
// ═══════════════════════════════════════════════════════════════════════════

/// Take rating for quick evaluation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TakeRating {
    #[default]
    None,
    Bad,
    Okay,
    Good,
    Best,
}

impl TakeRating {
    /// Rating as 0-5 score
    pub fn score(&self) -> u8 {
        match self {
            TakeRating::None => 0,
            TakeRating::Bad => 1,
            TakeRating::Okay => 2,
            TakeRating::Good => 3,
            TakeRating::Best => 4,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAKE
// ═══════════════════════════════════════════════════════════════════════════

/// A single take (recording pass)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Take {
    pub id: TakeId,
    pub lane_id: LaneId,
    pub track_id: TrackId,

    /// Take number (auto-incrementing per track)
    pub take_number: u32,

    /// Custom name
    pub name: Option<String>,

    /// Start time in seconds
    pub start_time: f64,

    /// Duration in seconds
    pub duration: f64,

    /// Source audio file path
    pub source_path: String,

    /// Source offset within audio file
    pub source_offset: f64,

    /// Original source duration
    pub source_duration: f64,

    /// Take rating
    pub rating: TakeRating,

    /// Recording timestamp (Unix epoch ms)
    pub recorded_at: u64,

    /// Is this take selected for the comp
    pub in_comp: bool,

    /// Gain adjustment (0-2, 1 = unity)
    pub gain: f64,

    /// Fade in duration
    pub fade_in: f64,

    /// Fade out duration
    pub fade_out: f64,

    /// Muted
    pub muted: bool,

    /// Locked (prevent edits)
    pub locked: bool,
}

impl Take {
    pub fn new(
        id: TakeId,
        lane_id: LaneId,
        track_id: TrackId,
        take_number: u32,
        source_path: impl Into<String>,
        start_time: f64,
        duration: f64,
    ) -> Self {
        Self {
            id,
            lane_id,
            track_id,
            take_number,
            name: None,
            start_time,
            duration,
            source_path: source_path.into(),
            source_offset: 0.0,
            source_duration: duration,
            rating: TakeRating::None,
            recorded_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            in_comp: false,
            gain: 1.0,
            fade_in: 0.0,
            fade_out: 0.0,
            muted: false,
            locked: false,
        }
    }

    pub fn end_time(&self) -> f64 {
        self.start_time + self.duration
    }

    pub fn display_name(&self) -> String {
        self.name
            .clone()
            .unwrap_or_else(|| format!("Take {}", self.take_number))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING LANE
// ═══════════════════════════════════════════════════════════════════════════

/// A recording lane within a track
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingLane {
    pub id: LaneId,
    pub track_id: TrackId,

    /// Display order (0 = topmost)
    pub index: u32,

    /// Lane name
    pub name: String,

    /// Lane height in pixels
    pub height: f64,

    /// Is visible (not collapsed)
    pub visible: bool,

    /// Is active for playback
    pub is_active: bool,

    /// Is comp lane (special composite playback)
    pub is_comp_lane: bool,

    /// Muted
    pub muted: bool,

    /// Lane color (ARGB)
    pub color: u32,

    /// Takes in this lane
    pub takes: Vec<Take>,
}

impl RecordingLane {
    pub fn new(id: LaneId, track_id: TrackId, index: u32) -> Self {
        Self {
            id,
            track_id,
            index,
            name: String::new(),
            height: 60.0,
            visible: true,
            is_active: index == 0,
            is_comp_lane: false,
            muted: false,
            color: 0xFF4A9EFF,
            takes: Vec::new(),
        }
    }

    pub fn display_name(&self) -> String {
        if self.name.is_empty() {
            format!("Lane {}", self.index + 1)
        } else {
            self.name.clone()
        }
    }

    /// Add a take
    pub fn add_take(&mut self, take: Take) {
        self.takes.push(take);
    }

    /// Remove a take
    pub fn remove_take(&mut self, take_id: TakeId) -> Option<Take> {
        if let Some(pos) = self.takes.iter().position(|t| t.id == take_id) {
            Some(self.takes.remove(pos))
        } else {
            None
        }
    }

    /// Get takes at a specific time
    pub fn takes_at(&self, time: f64) -> Vec<&Take> {
        self.takes
            .iter()
            .filter(|t| t.start_time <= time && t.end_time() >= time)
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMP REGION
// ═══════════════════════════════════════════════════════════════════════════

/// Crossfade type for comp region transitions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum CompCrossfadeType {
    Linear,
    #[default]
    EqualPower,
    SCurve,
}

/// A selected region from a specific take for the final comp
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompRegion {
    pub id: CompRegionId,
    pub track_id: TrackId,

    /// Which take this region comes from
    pub take_id: TakeId,

    /// Start time (timeline position)
    pub start_time: f64,

    /// End time
    pub end_time: f64,

    /// Crossfade in duration
    pub crossfade_in: f64,

    /// Crossfade out duration
    pub crossfade_out: f64,

    /// Crossfade type
    pub crossfade_type: CompCrossfadeType,
}

impl CompRegion {
    pub fn new(
        id: CompRegionId,
        track_id: TrackId,
        take_id: TakeId,
        start_time: f64,
        end_time: f64,
    ) -> Self {
        Self {
            id,
            track_id,
            take_id,
            start_time,
            end_time,
            crossfade_in: 0.01, // 10ms default
            crossfade_out: 0.01,
            crossfade_type: CompCrossfadeType::EqualPower,
        }
    }

    pub fn duration(&self) -> f64 {
        self.end_time - self.start_time
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMP MODE
// ═══════════════════════════════════════════════════════════════════════════

/// Comping playback mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum CompMode {
    /// Single lane playback
    #[default]
    Single,

    /// Comp mode (play from CompRegions)
    Comp,

    /// Audition all lanes stacked
    AuditAll,
}

// ═══════════════════════════════════════════════════════════════════════════
// COMP STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Track-level comping state
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CompState {
    pub track_id: TrackId,

    /// Current comping mode
    pub mode: CompMode,

    /// Is lane view expanded
    pub lanes_expanded: bool,

    /// Recording lanes
    pub lanes: Vec<RecordingLane>,

    /// Comp regions (for Comp mode)
    pub comp_regions: Vec<CompRegion>,

    /// Current active lane index
    pub active_lane_index: usize,

    /// Next take number (auto-increment)
    pub next_take_number: u32,

    /// Is currently recording
    pub is_recording: bool,

    /// Recording start time
    pub recording_start_time: Option<f64>,
}

impl CompState {
    pub fn new(track_id: TrackId) -> Self {
        Self {
            track_id,
            mode: CompMode::Single,
            lanes_expanded: false,
            lanes: Vec::new(),
            comp_regions: Vec::new(),
            active_lane_index: 0,
            next_take_number: 1,
            is_recording: false,
            recording_start_time: None,
        }
    }

    /// Get active lane
    pub fn active_lane(&self) -> Option<&RecordingLane> {
        self.lanes.get(self.active_lane_index)
    }

    /// Get active lane mutable
    pub fn active_lane_mut(&mut self) -> Option<&mut RecordingLane> {
        self.lanes.get_mut(self.active_lane_index)
    }

    /// Get all takes across all lanes
    pub fn all_takes(&self) -> Vec<&Take> {
        self.lanes.iter().flat_map(|l| l.takes.iter()).collect()
    }

    /// Get takes at a specific time
    pub fn takes_at(&self, time: f64) -> Vec<&Take> {
        self.lanes.iter().flat_map(|l| l.takes_at(time)).collect()
    }

    /// Create a new lane
    pub fn create_lane(&mut self) -> LaneId {
        let id = LaneId(self.lanes.len() as u64 + 1);
        let lane = RecordingLane::new(id, self.track_id, self.lanes.len() as u32);
        self.lanes.push(lane);
        id
    }

    /// Set active lane by index
    pub fn set_active_lane(&mut self, index: usize) {
        if index < self.lanes.len() {
            // Clear old active
            for lane in &mut self.lanes {
                lane.is_active = false;
            }
            // Set new active
            self.lanes[index].is_active = true;
            self.active_lane_index = index;
        }
    }

    /// Add a take to active lane
    pub fn add_take(&mut self, take: Take) {
        if let Some(lane) = self.active_lane_mut() {
            lane.add_take(take);
            self.next_take_number += 1;
        }
    }

    /// Start recording
    pub fn start_recording(&mut self, start_time: f64) {
        self.is_recording = true;
        self.recording_start_time = Some(start_time);
    }

    /// Stop recording
    pub fn stop_recording(&mut self) {
        self.is_recording = false;
        self.recording_start_time = None;
    }

    /// Add a comp region
    pub fn add_comp_region(&mut self, region: CompRegion) {
        self.comp_regions.push(region);
        self.comp_regions
            .sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        self.mode = CompMode::Comp;
    }

    /// Remove a comp region
    pub fn remove_comp_region(&mut self, id: CompRegionId) {
        self.comp_regions.retain(|r| r.id != id);
    }

    /// Clear all comp regions
    pub fn clear_comp(&mut self) {
        self.comp_regions.clear();
        self.mode = CompMode::Single;
    }

    /// Total lane height when expanded
    pub fn expanded_height(&self) -> f64 {
        self.lanes
            .iter()
            .filter(|l| l.visible)
            .map(|l| l.height)
            .sum()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPING MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Global comping state manager
#[derive(Debug, Default)]
pub struct CompingManager {
    /// Per-track comping state
    pub states: HashMap<TrackId, CompState>,

    /// Next ID counters
    next_lane_id: u64,
    next_take_id: u64,
    next_region_id: u64,
}

impl CompingManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Get or create comp state for a track
    pub fn get_or_create(&mut self, track_id: TrackId) -> &mut CompState {
        self.states
            .entry(track_id)
            .or_insert_with(|| CompState::new(track_id))
    }

    /// Get comp state for a track
    pub fn get(&self, track_id: TrackId) -> Option<&CompState> {
        self.states.get(&track_id)
    }

    /// Get comp state mutable
    pub fn get_mut(&mut self, track_id: TrackId) -> Option<&mut CompState> {
        self.states.get_mut(&track_id)
    }

    /// Generate new lane ID
    pub fn next_lane_id(&mut self) -> LaneId {
        self.next_lane_id += 1;
        LaneId(self.next_lane_id)
    }

    /// Generate new take ID
    pub fn next_take_id(&mut self) -> TakeId {
        self.next_take_id += 1;
        TakeId(self.next_take_id)
    }

    /// Generate new comp region ID
    pub fn next_region_id(&mut self) -> CompRegionId {
        self.next_region_id += 1;
        CompRegionId(self.next_region_id)
    }

    /// Clear all state
    pub fn clear(&mut self) {
        self.states.clear();
        self.next_lane_id = 0;
        self.next_take_id = 0;
        self.next_region_id = 0;
    }

    /// Remove track state
    pub fn remove_track(&mut self, track_id: TrackId) {
        self.states.remove(&track_id);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_comp_state_basic() {
        let track_id = TrackId(1);
        let mut state = CompState::new(track_id);

        // Create lanes
        let _lane1_id = state.create_lane();
        let _lane2_id = state.create_lane();

        assert_eq!(state.lanes.len(), 2);
        assert_eq!(state.active_lane_index, 0);

        // Set active lane
        state.set_active_lane(1);
        assert_eq!(state.active_lane_index, 1);
        assert!(state.lanes[1].is_active);
        assert!(!state.lanes[0].is_active);
    }

    #[test]
    fn test_take_creation() {
        let track_id = TrackId(1);
        let lane_id = LaneId(1);
        let take_id = TakeId(1);

        let take = Take::new(take_id, lane_id, track_id, 1, "/audio/take1.wav", 0.0, 5.0);

        assert_eq!(take.take_number, 1);
        assert_eq!(take.duration, 5.0);
        assert_eq!(take.end_time(), 5.0);
        assert_eq!(take.display_name(), "Take 1");
    }

    #[test]
    fn test_comp_region() {
        let track_id = TrackId(1);
        let take_id = TakeId(1);
        let region_id = CompRegionId(1);

        let region = CompRegion::new(region_id, track_id, take_id, 1.0, 3.0);

        assert_eq!(region.duration(), 2.0);
        assert_eq!(region.crossfade_type, CompCrossfadeType::EqualPower);
    }

    #[test]
    fn test_comping_manager() {
        let mut manager = CompingManager::new();
        let track_id = TrackId(1);

        // Get or create state
        let state = manager.get_or_create(track_id);
        state.create_lane();
        state.create_lane();

        // Should have 2 lanes
        assert_eq!(manager.get(track_id).unwrap().lanes.len(), 2);

        // Generate IDs
        let lane_id = manager.next_lane_id();
        assert_eq!(lane_id.0, 1);

        let take_id = manager.next_take_id();
        assert_eq!(take_id.0, 1);
    }
}
