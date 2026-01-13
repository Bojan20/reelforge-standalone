//! Unified Track Architecture (REAPER Style)
//!
//! Unlike traditional DAWs where Audio, MIDI, and Aux tracks are separate types,
//! FluxForge Studio uses a unified track model where any track can contain any data type.
//!
//! Benefits:
//! - No conceptual friction between track types
//! - Flexible routing (any track → any track)
//! - Natural folder/group hierarchy
//! - Up to 128 channels per track

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::Decibels;

/// Unique track identifier (u64 for large project support)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub struct TrackId(pub u64);

impl TrackId {
    pub fn new(id: u64) -> Self {
        Self(id)
    }

    /// Create from u32 (backwards compatibility)
    #[inline]
    pub fn from_u32(id: u32) -> Self {
        Self(id as u64)
    }

    /// Get as u64
    #[inline]
    pub fn as_u64(self) -> u64 {
        self.0
    }
}

/// Maximum channels per track (like REAPER's 64-channel architecture)
pub const MAX_TRACK_CHANNELS: usize = 128;

/// Track type hint (for UI, not for processing)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TrackTypeHint {
    /// General purpose track
    #[default]
    General,
    /// Primarily audio content
    Audio,
    /// Primarily MIDI content
    Midi,
    /// Primarily instrument output
    Instrument,
    /// Auxiliary/bus track
    Aux,
    /// Master output
    Master,
    /// Folder/group track
    Folder,
    /// Video track
    Video,
    /// VCA (Voltage Controlled Amplifier) fader
    Vca,
}

/// Track arm state for recording
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ArmState {
    /// Not armed for recording
    #[default]
    Disarmed,
    /// Armed for audio recording
    ArmedAudio,
    /// Armed for MIDI recording
    ArmedMidi,
    /// Armed for both
    ArmedBoth,
}

/// Track monitoring mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum MonitorMode {
    /// Auto monitoring (monitor when armed, playback when not)
    #[default]
    Auto,
    /// Always monitor input
    Input,
    /// Always playback (no monitoring)
    Off,
    /// Tape style (monitor only when not playing)
    TapeStyle,
}

/// Track phase setting
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum PhaseMode {
    #[default]
    Normal,
    /// Invert phase
    Inverted,
}

/// Track routing destination
#[derive(Debug, Clone, Serialize, Deserialize)]
#[derive(Default)]
pub enum RoutingDestination {
    /// Route to another track
    Track(TrackId),
    /// Route to hardware output
    HardwareOutput(usize),
    /// Route to master bus
    #[default]
    Master,
    /// No output (muted)
    None,
}


/// Send configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackSend {
    /// Destination track
    pub destination: TrackId,
    /// Send level
    pub level: Decibels,
    /// Pre/post fader
    pub pre_fader: bool,
    /// Pan position (-1.0 to 1.0)
    pub pan: f64,
    /// Muted
    pub muted: bool,
}

/// Track pan mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum PanMode {
    /// Standard stereo balance
    #[default]
    Balance,
    /// Stereo pan (dual mono)
    StereoPan,
    /// Mid/Side
    MidSide,
    /// Binaural/3D
    Binaural,
}

/// Unified Track
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    /// Unique identifier
    pub id: TrackId,
    /// Track name
    pub name: String,
    /// Track color (RGBA)
    pub color: u32,
    /// Type hint for UI
    pub type_hint: TrackTypeHint,
    /// Number of audio channels (1-128)
    pub num_channels: usize,

    // === Mixer State ===
    /// Volume in dB
    pub volume: Decibels,
    /// Pan position (-1.0 left to 1.0 right)
    pub pan: f64,
    /// Pan mode
    pub pan_mode: PanMode,
    /// Mute state
    pub muted: bool,
    /// Solo state
    pub soloed: bool,
    /// Phase mode
    pub phase: PhaseMode,

    // === Recording ===
    /// Arm state
    pub arm_state: ArmState,
    /// Monitor mode
    pub monitor_mode: MonitorMode,
    /// Input source (hardware input index)
    pub input_source: Option<usize>,

    // === Routing ===
    /// Output destination
    pub output: RoutingDestination,
    /// Sends
    pub sends: Vec<TrackSend>,

    // === Hierarchy ===
    /// Parent folder track (if any)
    pub parent: Option<TrackId>,
    /// Is this a folder track?
    pub is_folder: bool,
    /// Folder is expanded in UI
    pub folder_expanded: bool,

    // === VCA (Voltage Controlled Amplifier) ===
    /// VCA groups this track belongs to
    pub vca_groups: Vec<TrackId>,
    /// Is this track a VCA master?
    pub is_vca_master: bool,

    // === Processing ===
    /// Track is frozen (rendered to audio)
    pub frozen: bool,
    /// Track processing is bypassed
    pub bypassed: bool,
    /// Processing path (realtime vs guard)
    pub processing_path: ProcessingPath,

    // === Metadata ===
    /// Track index in project (for ordering)
    pub index: usize,
    /// Track height in UI (pixels)
    pub height: u32,
    /// Track is visible
    pub visible: bool,
    /// Track is locked (no editing)
    pub locked: bool,

    // === Custom ===
    /// User-defined tags
    pub tags: Vec<String>,
    /// Custom properties
    pub properties: HashMap<String, String>,
}

/// Processing path selection (ASIO-Guard equivalent)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ProcessingPath {
    /// Real-time processing (low latency)
    #[default]
    RealTime,
    /// Guard/prefetch processing (higher quality)
    Guard,
    /// Automatic based on monitoring state
    Auto,
}

impl Track {
    /// Create a new track with default settings
    pub fn new(id: TrackId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            color: 0x808080FF, // Gray
            type_hint: TrackTypeHint::General,
            num_channels: 2,

            volume: Decibels::ZERO,
            pan: 0.0,
            pan_mode: PanMode::Balance,
            muted: false,
            soloed: false,
            phase: PhaseMode::Normal,

            arm_state: ArmState::Disarmed,
            monitor_mode: MonitorMode::Auto,
            input_source: None,

            output: RoutingDestination::Master,
            sends: Vec::new(),

            parent: None,
            is_folder: false,
            folder_expanded: true,

            vca_groups: Vec::new(),
            is_vca_master: false,

            frozen: false,
            bypassed: false,
            processing_path: ProcessingPath::Auto,

            index: 0,
            height: 80,
            visible: true,
            locked: false,

            tags: Vec::new(),
            properties: HashMap::new(),
        }
    }

    /// Create an audio track
    pub fn audio(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Audio;
        track
    }

    /// Create a MIDI track
    pub fn midi(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Midi;
        track.num_channels = 2; // MIDI tracks still have audio output
        track
    }

    /// Create an instrument track
    pub fn instrument(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Instrument;
        track
    }

    /// Create an aux/bus track
    pub fn aux(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Aux;
        track
    }

    /// Create a folder track
    pub fn folder(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Folder;
        track.is_folder = true;
        track
    }

    /// Create master track
    pub fn master(id: TrackId) -> Self {
        let mut track = Self::new(id, "Master");
        track.type_hint = TrackTypeHint::Master;
        track.output = RoutingDestination::HardwareOutput(0);
        track
    }

    /// Create VCA (Voltage Controlled Amplifier) master track
    ///
    /// VCA faders control the volume of multiple tracks without
    /// affecting their individual fader positions. Unlike groups/buses,
    /// VCA doesn't sum audio - it just multiplies gain.
    pub fn vca(id: TrackId, name: impl Into<String>) -> Self {
        let mut track = Self::new(id, name);
        track.type_hint = TrackTypeHint::Vca;
        track.is_vca_master = true;
        // VCA doesn't route audio
        track.output = RoutingDestination::None;
        track
    }

    /// Add this track to a VCA group
    pub fn add_to_vca(&mut self, vca_id: TrackId) {
        if !self.vca_groups.contains(&vca_id) {
            self.vca_groups.push(vca_id);
        }
    }

    /// Remove this track from a VCA group
    pub fn remove_from_vca(&mut self, vca_id: TrackId) {
        self.vca_groups.retain(|&id| id != vca_id);
    }

    /// Check if track should use real-time processing
    pub fn needs_realtime(&self) -> bool {
        match self.processing_path {
            ProcessingPath::RealTime => true,
            ProcessingPath::Guard => false,
            ProcessingPath::Auto => {
                // Use realtime when monitoring or armed
                self.is_monitoring() || self.arm_state != ArmState::Disarmed
            }
        }
    }

    /// Check if track is currently monitoring input
    pub fn is_monitoring(&self) -> bool {
        match self.monitor_mode {
            MonitorMode::Input => true,
            MonitorMode::Off => false,
            MonitorMode::Auto => self.arm_state != ArmState::Disarmed,
            MonitorMode::TapeStyle => false, // Would check transport state
        }
    }

    /// Add a send
    pub fn add_send(&mut self, destination: TrackId, level: Decibels, pre_fader: bool) {
        self.sends.push(TrackSend {
            destination,
            level,
            pre_fader,
            pan: 0.0,
            muted: false,
        });
    }

    /// Calculate effective gain including mute/solo
    pub fn effective_gain(&self, any_soloed: bool) -> f64 {
        if self.muted {
            return 0.0;
        }
        if any_soloed && !self.soloed {
            return 0.0;
        }
        self.volume.to_gain()
    }
}

/// Track manager for a project
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TrackManager {
    /// All tracks (order matters)
    tracks: Vec<Track>,
    /// Next track ID
    next_id: u64,
    /// Master track ID
    master_id: Option<TrackId>,
}

impl TrackManager {
    pub fn new() -> Self {
        Self {
            tracks: Vec::new(),
            next_id: 1,
            master_id: None,
        }
    }

    /// Create with master track
    pub fn with_master() -> Self {
        let mut mgr = Self::new();
        let id = mgr.add_track(Track::master(TrackId::new(0)));
        mgr.master_id = Some(id);
        mgr
    }

    /// Add a track
    pub fn add_track(&mut self, mut track: Track) -> TrackId {
        let id = TrackId::new(self.next_id);
        self.next_id += 1;
        track.id = id;
        track.index = self.tracks.len();
        self.tracks.push(track);
        id
    }

    /// Get track by ID
    pub fn get(&self, id: TrackId) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == id)
    }

    /// Get mutable track by ID
    pub fn get_mut(&mut self, id: TrackId) -> Option<&mut Track> {
        self.tracks.iter_mut().find(|t| t.id == id)
    }

    /// Get all tracks
    pub fn all(&self) -> &[Track] {
        &self.tracks
    }

    /// Get tracks that need real-time processing
    pub fn realtime_tracks(&self) -> Vec<TrackId> {
        self.tracks
            .iter()
            .filter(|t| t.needs_realtime())
            .map(|t| t.id)
            .collect()
    }

    /// Get tracks that can use guard processing
    pub fn guard_tracks(&self) -> Vec<TrackId> {
        self.tracks
            .iter()
            .filter(|t| !t.needs_realtime())
            .map(|t| t.id)
            .collect()
    }

    /// Check if any track is soloed
    pub fn any_soloed(&self) -> bool {
        self.tracks.iter().any(|t| t.soloed)
    }

    /// Get master track
    pub fn master(&self) -> Option<&Track> {
        self.master_id.and_then(|id| self.get(id))
    }

    /// Get master track mutable
    pub fn master_mut(&mut self) -> Option<&mut Track> {
        self.master_id.and_then(|id| self.get_mut(id))
    }

    /// Remove track
    pub fn remove(&mut self, id: TrackId) -> Option<Track> {
        if let Some(pos) = self.tracks.iter().position(|t| t.id == id) {
            Some(self.tracks.remove(pos))
        } else {
            None
        }
    }

    /// Move track to new index
    pub fn move_track(&mut self, id: TrackId, new_index: usize) {
        if let Some(pos) = self.tracks.iter().position(|t| t.id == id) {
            let track = self.tracks.remove(pos);
            let insert_at = new_index.min(self.tracks.len());
            self.tracks.insert(insert_at, track);
            self.reindex();
        }
    }

    /// Reindex tracks after reordering
    fn reindex(&mut self) {
        for (i, track) in self.tracks.iter_mut().enumerate() {
            track.index = i;
        }
    }

    /// Get children of a folder track
    pub fn folder_children(&self, folder_id: TrackId) -> Vec<&Track> {
        self.tracks
            .iter()
            .filter(|t| t.parent == Some(folder_id))
            .collect()
    }

    /// Count tracks
    pub fn count(&self) -> usize {
        self.tracks.len()
    }

    /// Get VCA masters
    pub fn vca_masters(&self) -> Vec<&Track> {
        self.tracks.iter().filter(|t| t.is_vca_master).collect()
    }

    /// Calculate effective VCA gain for a track
    /// Multiplies gains from all VCA masters the track belongs to
    pub fn vca_gain(&self, track_id: TrackId) -> f64 {
        let track = match self.get(track_id) {
            Some(t) => t,
            None => return 1.0,
        };

        let mut gain = 1.0;
        let any_soloed = self.any_soloed();

        for vca_id in &track.vca_groups {
            if let Some(vca) = self.get(*vca_id) {
                gain *= vca.effective_gain(any_soloed);
            }
        }

        gain
    }

    /// Calculate total effective gain for a track including VCA
    pub fn total_effective_gain(&self, track_id: TrackId) -> f64 {
        let track = match self.get(track_id) {
            Some(t) => t,
            None => return 0.0,
        };

        let any_soloed = self.any_soloed();
        track.effective_gain(any_soloed) * self.vca_gain(track_id)
    }

    /// Get all tracks in a VCA group
    pub fn vca_members(&self, vca_id: TrackId) -> Vec<&Track> {
        self.tracks
            .iter()
            .filter(|t| t.vca_groups.contains(&vca_id))
            .collect()
    }

    /// Create a new VCA and return its ID
    pub fn create_vca(&mut self, name: impl Into<String>) -> TrackId {
        self.add_track(Track::vca(TrackId::new(0), name))
    }

    /// Add tracks to a VCA group
    pub fn add_to_vca_group(&mut self, track_ids: &[TrackId], vca_id: TrackId) {
        for id in track_ids {
            if let Some(track) = self.get_mut(*id) {
                track.add_to_vca(vca_id);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_tracks() {
        let mut mgr = TrackManager::with_master();

        let audio = mgr.add_track(Track::audio(TrackId::new(0), "Audio 1"));
        let midi = mgr.add_track(Track::midi(TrackId::new(0), "MIDI 1"));

        assert_eq!(mgr.count(), 3); // Master + 2 tracks

        let track = mgr.get(audio).unwrap();
        assert_eq!(track.type_hint, TrackTypeHint::Audio);
    }

    #[test]
    fn test_realtime_detection() {
        let mut track = Track::audio(TrackId::new(1), "Test");

        // Default: auto mode, not armed = guard ok
        assert!(!track.needs_realtime());

        // Armed = needs realtime
        track.arm_state = ArmState::ArmedAudio;
        assert!(track.needs_realtime());

        // Force guard mode
        track.processing_path = ProcessingPath::Guard;
        assert!(!track.needs_realtime());
    }

    #[test]
    fn test_effective_gain() {
        let mut track = Track::audio(TrackId::new(1), "Test");
        track.volume = Decibels(0.0);

        // Normal: full gain
        assert!((track.effective_gain(false) - 1.0).abs() < 0.001);

        // Muted: zero
        track.muted = true;
        assert_eq!(track.effective_gain(false), 0.0);

        // Not muted, but something else soloed and we're not
        track.muted = false;
        assert_eq!(track.effective_gain(true), 0.0);

        // We're soloed
        track.soloed = true;
        assert!((track.effective_gain(true) - 1.0).abs() < 0.001);
    }
}
