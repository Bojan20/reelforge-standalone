//! Track Manager - Cubase-style Track/Clip Management
//!
//! Provides:
//! - Track creation, deletion, reordering
//! - Clip management (move, resize, split, duplicate)
//! - Crossfade handling
//! - Undo/Redo command pattern
//! - Lock-free updates to audio thread

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use serde::{Deserialize, Serialize};
use parking_lot::RwLock;

// ═══════════════════════════════════════════════════════════════════════════
// ID TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Unique track identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TrackId(pub u64);

/// Unique clip identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ClipId(pub u64);

/// Unique crossfade identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CrossfadeId(pub u64);

/// Unique marker identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct MarkerId(pub u64);

// Global ID counter for generating unique IDs
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT BUS
// ═══════════════════════════════════════════════════════════════════════════

/// Output bus routing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OutputBus {
    Master = 0,
    Music = 1,
    Sfx = 2,
    Voice = 3,
    Ambience = 4,
    Aux = 5,
}

impl Default for OutputBus {
    fn default() -> Self {
        Self::Master
    }
}

impl From<u32> for OutputBus {
    fn from(value: u32) -> Self {
        match value {
            0 => Self::Master,
            1 => Self::Music,
            2 => Self::Sfx,
            3 => Self::Voice,
            4 => Self::Ambience,
            5 => Self::Aux,
            _ => Self::Master,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK
// ═══════════════════════════════════════════════════════════════════════════

/// Audio track with clips
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub id: TrackId,
    pub name: String,
    pub color: u32,           // ARGB color
    pub height: f64,          // UI height in pixels
    pub output_bus: OutputBus,
    pub volume: f64,          // 0.0 to 1.5 (linear, +6dB headroom)
    pub pan: f64,             // -1.0 to +1.0
    pub muted: bool,
    pub soloed: bool,
    pub armed: bool,
    pub locked: bool,
    pub frozen: bool,
    pub input_monitor: bool,
    pub order: usize,         // Position in track list
}

impl Track {
    pub fn new(name: &str, color: u32, output_bus: OutputBus) -> Self {
        Self {
            id: TrackId(next_id()),
            name: name.to_string(),
            color,
            height: 80.0,
            output_bus,
            volume: 1.0,
            pan: 0.0,
            muted: false,
            soloed: false,
            armed: false,
            locked: false,
            frozen: false,
            input_monitor: false,
            order: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP
// ═══════════════════════════════════════════════════════════════════════════

/// Audio clip on a track
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Clip {
    pub id: ClipId,
    pub track_id: TrackId,
    pub name: String,
    pub color: Option<u32>,   // Override track color if set

    // Timeline position (in seconds)
    pub start_time: f64,
    pub duration: f64,

    // Source audio reference
    pub source_file: String,  // Path to audio file
    pub source_offset: f64,   // Start offset within source (for trimming)
    pub source_duration: f64, // Original source file duration

    // Fades (in seconds)
    pub fade_in: f64,
    pub fade_out: f64,

    // Gain and state
    pub gain: f64,            // 0.0 to 2.0 (linear)
    pub muted: bool,
    pub selected: bool,
}

impl Clip {
    pub fn new(track_id: TrackId, name: &str, source_file: &str, start_time: f64, duration: f64) -> Self {
        Self {
            id: ClipId(next_id()),
            track_id,
            name: name.to_string(),
            color: None,
            start_time,
            duration,
            source_file: source_file.to_string(),
            source_offset: 0.0,
            source_duration: duration,
            fade_in: 0.0,
            fade_out: 0.0,
            gain: 1.0,
            muted: false,
            selected: false,
        }
    }

    /// End time on timeline
    #[inline]
    pub fn end_time(&self) -> f64 {
        self.start_time + self.duration
    }

    /// Check if this clip overlaps with another time range
    pub fn overlaps(&self, start: f64, end: f64) -> bool {
        self.start_time < end && self.end_time() > start
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE
// ═══════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CrossfadeCurve {
    Linear,
    EqualPower,
    SCurve,
}

impl Default for CrossfadeCurve {
    fn default() -> Self {
        Self::EqualPower
    }
}

/// Crossfade between two clips
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Crossfade {
    pub id: CrossfadeId,
    pub track_id: TrackId,
    pub clip_a_id: ClipId,
    pub clip_b_id: ClipId,
    pub start_time: f64,
    pub duration: f64,
    pub curve: CrossfadeCurve,
}

impl Crossfade {
    pub fn new(track_id: TrackId, clip_a: ClipId, clip_b: ClipId, start_time: f64, duration: f64) -> Self {
        Self {
            id: CrossfadeId(next_id()),
            track_id,
            clip_a_id: clip_a,
            clip_b_id: clip_b,
            start_time,
            duration,
            curve: CrossfadeCurve::default(),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARKER
// ═══════════════════════════════════════════════════════════════════════════

/// Timeline marker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Marker {
    pub id: MarkerId,
    pub time: f64,
    pub name: String,
    pub color: u32,
}

impl Marker {
    pub fn new(time: f64, name: &str, color: u32) -> Self {
        Self {
            id: MarkerId(next_id()),
            time,
            name: name.to_string(),
            color,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOOP REGION
// ═══════════════════════════════════════════════════════════════════════════

/// Loop region on timeline
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct LoopRegion {
    pub start: f64,
    pub end: f64,
    pub enabled: bool,
}

impl Default for LoopRegion {
    fn default() -> Self {
        Self {
            start: 0.0,
            end: 8.0,
            enabled: false,
        }
    }
}

impl LoopRegion {
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Central manager for all tracks, clips, crossfades, and markers
pub struct TrackManager {
    /// All tracks (pub for lock-free audio thread access via try_read)
    pub tracks: RwLock<HashMap<TrackId, Track>>,
    /// All clips (pub for lock-free audio thread access via try_read)
    pub clips: RwLock<HashMap<ClipId, Clip>>,
    /// Crossfades between clips
    pub crossfades: RwLock<HashMap<CrossfadeId, Crossfade>>,
    /// Timeline markers
    pub markers: RwLock<Vec<Marker>>,
    /// Loop region
    pub loop_region: RwLock<LoopRegion>,
    /// Track ordering
    pub track_order: RwLock<Vec<TrackId>>,
}

impl TrackManager {
    pub fn new() -> Self {
        Self {
            tracks: RwLock::new(HashMap::new()),
            clips: RwLock::new(HashMap::new()),
            crossfades: RwLock::new(HashMap::new()),
            markers: RwLock::new(Vec::new()),
            loop_region: RwLock::new(LoopRegion::default()),
            track_order: RwLock::new(Vec::new()),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRACK OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new track
    pub fn create_track(&self, name: &str, color: u32, output_bus: OutputBus) -> TrackId {
        let mut track = Track::new(name, color, output_bus);
        let id = track.id;

        // Set order to end
        let mut order = self.track_order.write();
        track.order = order.len();
        order.push(id);

        self.tracks.write().insert(id, track);
        id
    }

    /// Delete a track and all its clips
    pub fn delete_track(&self, track_id: TrackId) {
        // Remove all clips on this track
        let clip_ids: Vec<ClipId> = self.clips.read()
            .values()
            .filter(|c| c.track_id == track_id)
            .map(|c| c.id)
            .collect();

        for clip_id in clip_ids {
            self.delete_clip(clip_id);
        }

        // Remove from order
        self.track_order.write().retain(|&id| id != track_id);

        // Remove track
        self.tracks.write().remove(&track_id);
    }

    /// Get track by ID
    pub fn get_track(&self, track_id: TrackId) -> Option<Track> {
        self.tracks.read().get(&track_id).cloned()
    }

    /// Get all tracks in order
    pub fn get_all_tracks(&self) -> Vec<Track> {
        let tracks = self.tracks.read();
        let order = self.track_order.read();
        order.iter()
            .filter_map(|id| tracks.get(id).cloned())
            .collect()
    }

    /// Update track properties
    pub fn update_track<F>(&self, track_id: TrackId, f: F)
    where
        F: FnOnce(&mut Track),
    {
        if let Some(track) = self.tracks.write().get_mut(&track_id) {
            f(track);
        }
    }

    /// Reorder tracks
    pub fn reorder_tracks(&self, new_order: Vec<TrackId>) {
        let mut order = self.track_order.write();
        *order = new_order;

        // Update track order fields
        let mut tracks = self.tracks.write();
        for (idx, id) in order.iter().enumerate() {
            if let Some(track) = tracks.get_mut(id) {
                track.order = idx;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLIP OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a new clip
    pub fn add_clip(&self, clip: Clip) -> ClipId {
        let id = clip.id;
        self.clips.write().insert(id, clip);
        id
    }

    /// Create and add a clip from an imported audio file
    pub fn create_clip(
        &self,
        track_id: TrackId,
        name: &str,
        source_file: &str,
        start_time: f64,
        duration: f64,
        source_duration: f64,
    ) -> ClipId {
        let mut clip = Clip::new(track_id, name, source_file, start_time, duration);
        clip.source_duration = source_duration;
        self.add_clip(clip)
    }

    /// Delete a clip
    pub fn delete_clip(&self, clip_id: ClipId) {
        // Remove associated crossfades
        let xfade_ids: Vec<CrossfadeId> = self.crossfades.read()
            .values()
            .filter(|x| x.clip_a_id == clip_id || x.clip_b_id == clip_id)
            .map(|x| x.id)
            .collect();

        for xfade_id in xfade_ids {
            self.crossfades.write().remove(&xfade_id);
        }

        self.clips.write().remove(&clip_id);
    }

    /// Get clip by ID
    pub fn get_clip(&self, clip_id: ClipId) -> Option<Clip> {
        self.clips.read().get(&clip_id).cloned()
    }

    /// Get all clips for a track
    pub fn get_clips_for_track(&self, track_id: TrackId) -> Vec<Clip> {
        self.clips.read()
            .values()
            .filter(|c| c.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Get all clips sorted by start time
    pub fn get_all_clips(&self) -> Vec<Clip> {
        let mut clips: Vec<_> = self.clips.read().values().cloned().collect();
        clips.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        clips
    }

    /// Move clip to new position (and optionally new track)
    pub fn move_clip(&self, clip_id: ClipId, new_track_id: TrackId, new_start_time: f64) {
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
            clip.track_id = new_track_id;
            clip.start_time = new_start_time.max(0.0);
        }
    }

    /// Resize clip (change start, duration, and source offset)
    pub fn resize_clip(
        &self,
        clip_id: ClipId,
        new_start_time: f64,
        new_duration: f64,
        new_source_offset: f64,
    ) {
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
            clip.start_time = new_start_time.max(0.0);
            clip.duration = new_duration.max(0.001);
            clip.source_offset = new_source_offset.max(0.0);
        }
    }

    /// Split clip at given time, returns IDs of both resulting clips
    pub fn split_clip(&self, clip_id: ClipId, split_time: f64) -> Option<(ClipId, ClipId)> {
        let original = self.get_clip(clip_id)?;

        // Validate split point is within clip
        if split_time <= original.start_time || split_time >= original.end_time() {
            return None;
        }

        let split_offset = split_time - original.start_time;

        // Create left clip (modify original in place)
        {
            let mut clips = self.clips.write();
            if let Some(clip) = clips.get_mut(&clip_id) {
                clip.duration = split_offset;
                clip.name = format!("{} (L)", original.name);
            }
        }

        // Create right clip
        let mut right_clip = Clip::new(
            original.track_id,
            &format!("{} (R)", original.name),
            &original.source_file,
            split_time,
            original.duration - split_offset,
        );
        right_clip.source_offset = original.source_offset + split_offset;
        right_clip.source_duration = original.source_duration;
        right_clip.gain = original.gain;
        right_clip.color = original.color;

        let right_id = self.add_clip(right_clip);

        Some((clip_id, right_id))
    }

    /// Duplicate a clip
    pub fn duplicate_clip(&self, clip_id: ClipId) -> Option<ClipId> {
        let original = self.get_clip(clip_id)?;

        let mut new_clip = Clip::new(
            original.track_id,
            &format!("{} (copy)", original.name),
            &original.source_file,
            original.end_time(), // Place after original
            original.duration,
        );
        new_clip.source_offset = original.source_offset;
        new_clip.source_duration = original.source_duration;
        new_clip.fade_in = original.fade_in;
        new_clip.fade_out = original.fade_out;
        new_clip.gain = original.gain;
        new_clip.color = original.color;

        Some(self.add_clip(new_clip))
    }

    /// Update clip properties
    pub fn update_clip<F>(&self, clip_id: ClipId, f: F)
    where
        F: FnOnce(&mut Clip),
    {
        if let Some(clip) = self.clips.write().get_mut(&clip_id) {
            f(clip);
        }
    }

    /// Set clip selection state
    pub fn select_clip(&self, clip_id: ClipId, selected: bool) {
        self.update_clip(clip_id, |c| c.selected = selected);
    }

    /// Clear all clip selections
    pub fn clear_selection(&self) {
        for clip in self.clips.write().values_mut() {
            clip.selected = false;
        }
    }

    /// Get selected clips
    pub fn get_selected_clips(&self) -> Vec<Clip> {
        self.clips.read()
            .values()
            .filter(|c| c.selected)
            .cloned()
            .collect()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSSFADE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create crossfade between two adjacent clips
    pub fn create_crossfade(
        &self,
        clip_a_id: ClipId,
        clip_b_id: ClipId,
        duration: f64,
        curve: CrossfadeCurve,
    ) -> Option<CrossfadeId> {
        let clip_a = self.get_clip(clip_a_id)?;
        let clip_b = self.get_clip(clip_b_id)?;

        // Clips must be on same track
        if clip_a.track_id != clip_b.track_id {
            return None;
        }

        // Determine crossfade start (overlap point)
        let start_time = clip_a.end_time() - duration / 2.0;

        let mut xfade = Crossfade::new(
            clip_a.track_id,
            clip_a_id,
            clip_b_id,
            start_time,
            duration,
        );
        xfade.curve = curve;

        let id = xfade.id;
        self.crossfades.write().insert(id, xfade);

        Some(id)
    }

    /// Get all crossfades for a track
    pub fn get_crossfades_for_track(&self, track_id: TrackId) -> Vec<Crossfade> {
        self.crossfades.read()
            .values()
            .filter(|x| x.track_id == track_id)
            .cloned()
            .collect()
    }

    /// Update crossfade
    pub fn update_crossfade(&self, xfade_id: CrossfadeId, duration: f64, curve: CrossfadeCurve) {
        if let Some(xfade) = self.crossfades.write().get_mut(&xfade_id) {
            xfade.duration = duration;
            xfade.curve = curve;
        }
    }

    /// Delete crossfade
    pub fn delete_crossfade(&self, xfade_id: CrossfadeId) {
        self.crossfades.write().remove(&xfade_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARKER OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Add marker
    pub fn add_marker(&self, time: f64, name: &str, color: u32) -> MarkerId {
        let marker = Marker::new(time, name, color);
        let id = marker.id;
        self.markers.write().push(marker);
        id
    }

    /// Get all markers sorted by time
    pub fn get_markers(&self) -> Vec<Marker> {
        let mut markers = self.markers.read().clone();
        markers.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap());
        markers
    }

    /// Delete marker
    pub fn delete_marker(&self, marker_id: MarkerId) {
        self.markers.write().retain(|m| m.id != marker_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOOP REGION
    // ═══════════════════════════════════════════════════════════════════════

    /// Get loop region
    pub fn get_loop_region(&self) -> LoopRegion {
        *self.loop_region.read()
    }

    /// Set loop region
    pub fn set_loop_region(&self, start: f64, end: f64) {
        let mut region = self.loop_region.write();
        region.start = start.max(0.0);
        region.end = end.max(start + 0.001);
    }

    /// Enable/disable loop
    pub fn set_loop_enabled(&self, enabled: bool) {
        self.loop_region.write().enabled = enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROJECT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Clear all data (new project)
    pub fn clear(&self) {
        self.tracks.write().clear();
        self.clips.write().clear();
        self.crossfades.write().clear();
        self.markers.write().clear();
        self.track_order.write().clear();
        *self.loop_region.write() = LoopRegion::default();
    }

    /// Get total project duration (end of last clip)
    pub fn get_duration(&self) -> f64 {
        self.clips.read()
            .values()
            .map(|c| c.end_time())
            .fold(0.0, f64::max)
    }

    /// Get track count
    pub fn track_count(&self) -> usize {
        self.tracks.read().len()
    }

    /// Get clip count
    pub fn clip_count(&self) -> usize {
        self.clips.read().len()
    }
}

impl Default for TrackManager {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_track() {
        let manager = TrackManager::new();
        let id = manager.create_track("Audio 1", 0xFF4A9EFF, OutputBus::Master);

        let track = manager.get_track(id).unwrap();
        assert_eq!(track.name, "Audio 1");
        assert_eq!(track.output_bus, OutputBus::Master);
    }

    #[test]
    fn test_create_and_move_clip() {
        let manager = TrackManager::new();
        let track1 = manager.create_track("Track 1", 0xFF0000FF, OutputBus::Master);
        let track2 = manager.create_track("Track 2", 0xFFFF0000, OutputBus::Music);

        let clip_id = manager.create_clip(track1, "Clip", "audio.wav", 1.0, 4.0, 4.0);

        // Move to track 2 at time 5.0
        manager.move_clip(clip_id, track2, 5.0);

        let clip = manager.get_clip(clip_id).unwrap();
        assert_eq!(clip.track_id, track2);
        assert_eq!(clip.start_time, 5.0);
    }

    #[test]
    fn test_split_clip() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);
        let clip_id = manager.create_clip(track, "Clip", "audio.wav", 0.0, 4.0, 4.0);

        let (left_id, right_id) = manager.split_clip(clip_id, 2.0).unwrap();

        let left = manager.get_clip(left_id).unwrap();
        let right = manager.get_clip(right_id).unwrap();

        assert_eq!(left.duration, 2.0);
        assert_eq!(right.start_time, 2.0);
        assert_eq!(right.duration, 2.0);
    }

    #[test]
    fn test_duplicate_clip() {
        let manager = TrackManager::new();
        let track = manager.create_track("Track", 0xFF00FF00, OutputBus::Master);
        let clip_id = manager.create_clip(track, "Clip", "audio.wav", 0.0, 4.0, 4.0);

        let dup_id = manager.duplicate_clip(clip_id).unwrap();
        let dup = manager.get_clip(dup_id).unwrap();

        assert_eq!(dup.start_time, 4.0); // Placed after original
        assert_eq!(dup.duration, 4.0);
    }

    #[test]
    fn test_loop_region() {
        let manager = TrackManager::new();
        manager.set_loop_region(4.0, 12.0);
        manager.set_loop_enabled(true);

        let region = manager.get_loop_region();
        assert_eq!(region.start, 4.0);
        assert_eq!(region.end, 12.0);
        assert!(region.enabled);
    }
}
