//! Concrete Command Implementations for DAW Operations
//!
//! Provides undoable commands for:
//! - Track operations (add, remove, rename, reorder)
//! - Clip operations (add, remove, move, resize, split)
//! - Mixer operations (volume, pan, mute, solo)
//! - Automation operations
//! - Project settings

use parking_lot::RwLock;
use std::sync::Arc;

use crate::{AutomationPointState, Command, Project, RegionState, TrackState};

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a new track
pub struct AddTrackCommand {
    project: Arc<RwLock<Project>>,
    track: TrackState,
    index: Option<usize>,
    inserted_index: usize,
}

impl AddTrackCommand {
    pub fn new(project: Arc<RwLock<Project>>, track: TrackState, index: Option<usize>) -> Self {
        Self {
            project,
            track,
            index,
            inserted_index: 0,
        }
    }
}

impl Command for AddTrackCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        match self.index {
            Some(idx) => {
                let idx = idx.min(project.tracks.len());
                project.tracks.insert(idx, self.track.clone());
                self.inserted_index = idx;
            }
            None => {
                project.tracks.push(self.track.clone());
                self.inserted_index = project.tracks.len() - 1;
            }
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if self.inserted_index < project.tracks.len() {
            project.tracks.remove(self.inserted_index);
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Add Track"
    }
}

/// Remove a track
pub struct RemoveTrackCommand {
    project: Arc<RwLock<Project>>,
    index: usize,
    removed_track: Option<TrackState>,
}

impl RemoveTrackCommand {
    pub fn new(project: Arc<RwLock<Project>>, index: usize) -> Self {
        Self {
            project,
            index,
            removed_track: None,
        }
    }
}

impl Command for RemoveTrackCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if self.index < project.tracks.len() {
            self.removed_track = Some(project.tracks.remove(self.index));
        }
        project.touch();
    }

    fn undo(&mut self) {
        if let Some(track) = self.removed_track.take() {
            let mut project = self.project.write();
            let idx = self.index.min(project.tracks.len());
            project.tracks.insert(idx, track);
            project.touch();
        }
    }

    fn name(&self) -> &str {
        "Remove Track"
    }
}

/// Rename a track
pub struct RenameTrackCommand {
    project: Arc<RwLock<Project>>,
    index: usize,
    old_name: String,
    new_name: String,
}

impl RenameTrackCommand {
    pub fn new(project: Arc<RwLock<Project>>, index: usize, new_name: String) -> Self {
        let old_name = {
            let p = project.read();
            p.tracks
                .get(index)
                .map(|t| t.name.clone())
                .unwrap_or_default()
        };
        Self {
            project,
            index,
            old_name,
            new_name,
        }
    }
}

impl Command for RenameTrackCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.index) {
            track.name = self.new_name.clone();
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.index) {
            track.name = self.old_name.clone();
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Rename Track"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Rename Track"
    }
}

/// Reorder tracks
pub struct ReorderTrackCommand {
    project: Arc<RwLock<Project>>,
    from_index: usize,
    to_index: usize,
}

impl ReorderTrackCommand {
    pub fn new(project: Arc<RwLock<Project>>, from: usize, to: usize) -> Self {
        Self {
            project,
            from_index: from,
            to_index: to,
        }
    }
}

impl Command for ReorderTrackCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if self.from_index < project.tracks.len() && self.to_index < project.tracks.len() {
            let track = project.tracks.remove(self.from_index);
            project.tracks.insert(self.to_index, track);
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if self.to_index < project.tracks.len() && self.from_index < project.tracks.len() {
            let track = project.tracks.remove(self.to_index);
            project.tracks.insert(self.from_index, track);
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Reorder Track"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIP/REGION COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a clip/region to a track
pub struct AddClipCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    clip: RegionState,
    inserted_index: usize,
}

impl AddClipCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize, clip: RegionState) -> Self {
        Self {
            project,
            track_index,
            clip,
            inserted_index: 0,
        }
    }
}

impl Command for AddClipCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.regions.push(self.clip.clone());
            self.inserted_index = track.regions.len() - 1;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && self.inserted_index < track.regions.len()
        {
            track.regions.remove(self.inserted_index);
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Add Clip"
    }
}

/// Remove a clip/region
pub struct RemoveClipCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    clip_index: usize,
    removed_clip: Option<RegionState>,
}

impl RemoveClipCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize, clip_index: usize) -> Self {
        Self {
            project,
            track_index,
            clip_index,
            removed_clip: None,
        }
    }
}

impl Command for RemoveClipCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && self.clip_index < track.regions.len()
        {
            self.removed_clip = Some(track.regions.remove(self.clip_index));
        }
        project.touch();
    }

    fn undo(&mut self) {
        if let Some(clip) = self.removed_clip.take() {
            let mut project = self.project.write();
            if let Some(track) = project.tracks.get_mut(self.track_index) {
                let idx = self.clip_index.min(track.regions.len());
                track.regions.insert(idx, clip);
            }
            project.touch();
        }
    }

    fn name(&self) -> &str {
        "Remove Clip"
    }
}

/// Move a clip to a new position
pub struct MoveClipCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    clip_index: usize,
    old_position: u64,
    new_position: u64,
}

impl MoveClipCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        clip_index: usize,
        new_position: u64,
    ) -> Self {
        let old_position = {
            let p = project.read();
            p.tracks
                .get(track_index)
                .and_then(|t| t.regions.get(clip_index))
                .map(|r| r.position)
                .unwrap_or(0)
        };
        Self {
            project,
            track_index,
            clip_index,
            old_position,
            new_position,
        }
    }
}

impl Command for MoveClipCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(clip) = track.regions.get_mut(self.clip_index)
        {
            clip.position = self.new_position;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(clip) = track.regions.get_mut(self.clip_index)
        {
            clip.position = self.old_position;
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Move Clip"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Move Clip"
    }

    fn merge(&mut self, other: Box<dyn Command>) {
        // Keep old position from self, take new position from other
        // We need to downcast - for now just update new position
        // In production, would use Any trait
        let _ = other;
    }
}

/// Resize a clip
pub struct ResizeClipCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    clip_index: usize,
    old_length: u64,
    new_length: u64,
}

impl ResizeClipCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        clip_index: usize,
        new_length: u64,
    ) -> Self {
        let old_length = {
            let p = project.read();
            p.tracks
                .get(track_index)
                .and_then(|t| t.regions.get(clip_index))
                .map(|r| r.length)
                .unwrap_or(0)
        };
        Self {
            project,
            track_index,
            clip_index,
            old_length,
            new_length,
        }
    }
}

impl Command for ResizeClipCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(clip) = track.regions.get_mut(self.clip_index)
        {
            clip.length = self.new_length;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(clip) = track.regions.get_mut(self.clip_index)
        {
            clip.length = self.old_length;
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Resize Clip"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Resize Clip"
    }
}

/// Split a clip at position
pub struct SplitClipCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    clip_index: usize,
    split_position: u64,
    original_clip: Option<RegionState>,
}

impl SplitClipCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        clip_index: usize,
        split_position: u64,
    ) -> Self {
        Self {
            project,
            track_index,
            clip_index,
            split_position,
            original_clip: None,
        }
    }
}

impl Command for SplitClipCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(clip) = track.regions.get_mut(self.clip_index)
        {
            // Store original for undo
            self.original_clip = Some(clip.clone());

            // Calculate split point relative to clip
            let relative_split = self.split_position.saturating_sub(clip.position);

            if relative_split > 0 && relative_split < clip.length {
                // Create second half
                let mut second_half = clip.clone();
                second_half.id = format!("{}_split", clip.id);
                second_half.position = self.split_position;
                second_half.source_offset = clip.source_offset + relative_split;
                second_half.length = clip.length - relative_split;

                // Trim first half
                clip.length = relative_split;

                // Insert second half after first
                track.regions.insert(self.clip_index + 1, second_half);
            }
        }
        project.touch();
    }

    fn undo(&mut self) {
        if let Some(original) = self.original_clip.take() {
            let mut project = self.project.write();
            if let Some(track) = project.tracks.get_mut(self.track_index) {
                // Remove the second half if it exists
                if self.clip_index + 1 < track.regions.len() {
                    track.regions.remove(self.clip_index + 1);
                }
                // Restore original
                if self.clip_index < track.regions.len() {
                    track.regions[self.clip_index] = original;
                }
            }
            project.touch();
        }
    }

    fn name(&self) -> &str {
        "Split Clip"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIXER COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Change track volume
pub struct SetTrackVolumeCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    old_volume: f64,
    new_volume: f64,
}

impl SetTrackVolumeCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize, new_volume: f64) -> Self {
        let old_volume = {
            let p = project.read();
            p.tracks
                .get(track_index)
                .map(|t| t.volume_db)
                .unwrap_or(0.0)
        };
        Self {
            project,
            track_index,
            old_volume,
            new_volume,
        }
    }
}

impl Command for SetTrackVolumeCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.volume_db = self.new_volume;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.volume_db = self.old_volume;
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Set Volume"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Set Volume"
    }
}

/// Change track pan
pub struct SetTrackPanCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    old_pan: f64,
    new_pan: f64,
}

impl SetTrackPanCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize, new_pan: f64) -> Self {
        let old_pan = {
            let p = project.read();
            p.tracks.get(track_index).map(|t| t.pan).unwrap_or(0.0)
        };
        Self {
            project,
            track_index,
            old_pan,
            new_pan,
        }
    }
}

impl Command for SetTrackPanCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.pan = self.new_pan;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.pan = self.old_pan;
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Set Pan"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Set Pan"
    }
}

/// Toggle track mute
pub struct ToggleTrackMuteCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
}

impl ToggleTrackMuteCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize) -> Self {
        Self {
            project,
            track_index,
        }
    }
}

impl Command for ToggleTrackMuteCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.mute = !track.mute;
        }
        project.touch();
    }

    fn undo(&mut self) {
        // Toggle is its own inverse
        self.execute();
    }

    fn name(&self) -> &str {
        "Toggle Mute"
    }
}

/// Toggle track solo
pub struct ToggleTrackSoloCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
}

impl ToggleTrackSoloCommand {
    pub fn new(project: Arc<RwLock<Project>>, track_index: usize) -> Self {
        Self {
            project,
            track_index,
        }
    }
}

impl Command for ToggleTrackSoloCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index) {
            track.solo = !track.solo;
        }
        project.touch();
    }

    fn undo(&mut self) {
        self.execute();
    }

    fn name(&self) -> &str {
        "Toggle Solo"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Add automation point
pub struct AddAutomationPointCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    lane_index: usize,
    point: AutomationPointState,
    inserted_index: usize,
}

impl AddAutomationPointCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        lane_index: usize,
        point: AutomationPointState,
    ) -> Self {
        Self {
            project,
            track_index,
            lane_index,
            point,
            inserted_index: 0,
        }
    }
}

impl Command for AddAutomationPointCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(lane) = track.automation.get_mut(self.lane_index)
        {
            // Insert in sorted order
            let pos = lane
                .points
                .iter()
                .position(|p| p.position > self.point.position)
                .unwrap_or(lane.points.len());
            lane.points.insert(pos, self.point.clone());
            self.inserted_index = pos;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(lane) = track.automation.get_mut(self.lane_index)
            && self.inserted_index < lane.points.len()
        {
            lane.points.remove(self.inserted_index);
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Add Automation Point"
    }
}

/// Move automation point
pub struct MoveAutomationPointCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    lane_index: usize,
    point_index: usize,
    old_position: u64,
    old_value: f64,
    new_position: u64,
    new_value: f64,
}

impl MoveAutomationPointCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        lane_index: usize,
        point_index: usize,
        new_position: u64,
        new_value: f64,
    ) -> Self {
        let (old_position, old_value) = {
            let p = project.read();
            p.tracks
                .get(track_index)
                .and_then(|t| t.automation.get(lane_index))
                .and_then(|l| l.points.get(point_index))
                .map(|p| (p.position, p.value))
                .unwrap_or((0, 0.0))
        };
        Self {
            project,
            track_index,
            lane_index,
            point_index,
            old_position,
            old_value,
            new_position,
            new_value,
        }
    }
}

impl Command for MoveAutomationPointCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(lane) = track.automation.get_mut(self.lane_index)
            && let Some(point) = lane.points.get_mut(self.point_index)
        {
            point.position = self.new_position;
            point.value = self.new_value;
        }
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(lane) = track.automation.get_mut(self.lane_index)
            && let Some(point) = lane.points.get_mut(self.point_index)
        {
            point.position = self.old_position;
            point.value = self.old_value;
        }
        project.touch();
    }

    fn name(&self) -> &str {
        "Move Automation Point"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Move Automation Point"
    }
}

/// Delete automation point
pub struct DeleteAutomationPointCommand {
    project: Arc<RwLock<Project>>,
    track_index: usize,
    lane_index: usize,
    point_index: usize,
    removed_point: Option<AutomationPointState>,
}

impl DeleteAutomationPointCommand {
    pub fn new(
        project: Arc<RwLock<Project>>,
        track_index: usize,
        lane_index: usize,
        point_index: usize,
    ) -> Self {
        Self {
            project,
            track_index,
            lane_index,
            point_index,
            removed_point: None,
        }
    }
}

impl Command for DeleteAutomationPointCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        if let Some(track) = project.tracks.get_mut(self.track_index)
            && let Some(lane) = track.automation.get_mut(self.lane_index)
            && self.point_index < lane.points.len()
        {
            self.removed_point = Some(lane.points.remove(self.point_index));
        }
        project.touch();
    }

    fn undo(&mut self) {
        if let Some(point) = self.removed_point.take() {
            let mut project = self.project.write();
            if let Some(track) = project.tracks.get_mut(self.track_index)
                && let Some(lane) = track.automation.get_mut(self.lane_index)
            {
                let idx = self.point_index.min(lane.points.len());
                lane.points.insert(idx, point);
            }
            project.touch();
        }
    }

    fn name(&self) -> &str {
        "Delete Automation Point"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROJECT COMMANDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Change project tempo
pub struct SetTempoCommand {
    project: Arc<RwLock<Project>>,
    old_tempo: f64,
    new_tempo: f64,
}

impl SetTempoCommand {
    pub fn new(project: Arc<RwLock<Project>>, new_tempo: f64) -> Self {
        let old_tempo = project.read().tempo;
        Self {
            project,
            old_tempo,
            new_tempo,
        }
    }
}

impl Command for SetTempoCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        project.tempo = self.new_tempo;
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        project.tempo = self.old_tempo;
        project.touch();
    }

    fn name(&self) -> &str {
        "Set Tempo"
    }

    fn can_merge(&self, other: &dyn Command) -> bool {
        other.name() == "Set Tempo"
    }
}

/// Set loop region
pub struct SetLoopRegionCommand {
    project: Arc<RwLock<Project>>,
    old_enabled: bool,
    old_start: u64,
    old_end: u64,
    new_enabled: bool,
    new_start: u64,
    new_end: u64,
}

impl SetLoopRegionCommand {
    pub fn new(project: Arc<RwLock<Project>>, enabled: bool, start: u64, end: u64) -> Self {
        let (old_enabled, old_start, old_end) = {
            let p = project.read();
            (p.loop_enabled, p.loop_start, p.loop_end)
        };
        Self {
            project,
            old_enabled,
            old_start,
            old_end,
            new_enabled: enabled,
            new_start: start,
            new_end: end,
        }
    }
}

impl Command for SetLoopRegionCommand {
    fn execute(&mut self) {
        let mut project = self.project.write();
        project.loop_enabled = self.new_enabled;
        project.loop_start = self.new_start;
        project.loop_end = self.new_end;
        project.touch();
    }

    fn undo(&mut self) {
        let mut project = self.project.write();
        project.loop_enabled = self.old_enabled;
        project.loop_start = self.old_start;
        project.loop_end = self.old_end;
        project.touch();
    }

    fn name(&self) -> &str {
        "Set Loop Region"
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{TrackType, UndoManager};

    fn test_project() -> Arc<RwLock<Project>> {
        Arc::new(RwLock::new(Project::default()))
    }

    #[test]
    fn test_add_remove_track() {
        let project = test_project();
        let mut manager = UndoManager::new(100);

        // Add track
        let track = TrackState {
            id: "track1".to_string(),
            name: "Test Track".to_string(),
            track_type: TrackType::Audio,
            output_bus: "Master".to_string(),
            volume_db: 0.0,
            pan: 0.0,
            mute: false,
            solo: false,
            armed: false,
            color: None,
            regions: Vec::new(),
            automation: Vec::new(),
        };

        manager.execute(Box::new(AddTrackCommand::new(project.clone(), track, None)));
        assert_eq!(project.read().tracks.len(), 1);

        // Undo
        manager.undo();
        assert_eq!(project.read().tracks.len(), 0);

        // Redo
        manager.redo();
        assert_eq!(project.read().tracks.len(), 1);
    }

    #[test]
    fn test_set_tempo() {
        let project = test_project();
        let mut manager = UndoManager::new(100);

        assert_eq!(project.read().tempo, 120.0);

        manager.execute(Box::new(SetTempoCommand::new(project.clone(), 140.0)));
        assert_eq!(project.read().tempo, 140.0);

        manager.undo();
        assert_eq!(project.read().tempo, 120.0);
    }
}
