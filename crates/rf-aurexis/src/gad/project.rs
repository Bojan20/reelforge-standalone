//! GAD Project — manages dual timeline + tracks as a coherent project.

use serde::{Deserialize, Serialize};
use super::timeline::DualTimeline;
use super::tracks::{GadTrack, GadTrackType};

/// Track layout descriptor for project initialization.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GadTrackLayout {
    pub name: String,
    pub track_type: GadTrackType,
}

/// GAD project configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GadProjectConfig {
    /// Project name.
    pub name: String,
    /// Sample rate.
    pub sample_rate: u32,
    /// Initial BPM.
    pub bpm: f64,
    /// Length in bars.
    pub length_bars: u32,
    /// Gameplay frame rate.
    pub frame_rate: f64,
    /// Initial track layout.
    pub track_layout: Vec<GadTrackLayout>,
}

impl Default for GadProjectConfig {
    fn default() -> Self {
        Self {
            name: "Untitled GAD Project".into(),
            sample_rate: 48000,
            bpm: 120.0,
            length_bars: 32,
            frame_rate: 60.0,
            track_layout: vec![
                GadTrackLayout { name: "Music Base".into(), track_type: GadTrackType::MusicLayer },
                GadTrackLayout { name: "Music Wins".into(), track_type: GadTrackType::MusicLayer },
                GadTrackLayout { name: "Reels".into(), track_type: GadTrackType::ReelBound },
                GadTrackLayout { name: "Transients".into(), track_type: GadTrackType::Transient },
                GadTrackLayout { name: "Cascades".into(), track_type: GadTrackType::CascadeLayer },
                GadTrackLayout { name: "Jackpot".into(), track_type: GadTrackType::JackpotLadder },
                GadTrackLayout { name: "UI".into(), track_type: GadTrackType::Ui },
                GadTrackLayout { name: "Ambience".into(), track_type: GadTrackType::AmbientPad },
            ],
        }
    }
}

/// A complete GAD project.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GadProject {
    pub config: GadProjectConfig,
    pub timeline: DualTimeline,
    pub tracks: Vec<GadTrack>,
    /// Whether the project has been modified since last save.
    #[serde(skip)]
    pub dirty: bool,
}

impl GadProject {
    /// Create a new project from config.
    pub fn new(config: GadProjectConfig) -> Self {
        let timeline = DualTimeline::new(config.bpm, config.length_bars, config.frame_rate);
        let tracks: Vec<GadTrack> = config.track_layout.iter().enumerate().map(|(i, layout)| {
            let mut track = GadTrack::new(
                format!("track_{}", i),
                &layout.name,
                layout.track_type,
            );
            track.order = i as u32;
            track
        }).collect();

        Self {
            config,
            timeline,
            tracks,
            dirty: false,
        }
    }

    /// Create with default config.
    pub fn default_project() -> Self {
        Self::new(GadProjectConfig::default())
    }

    /// Add a track.
    pub fn add_track(&mut self, name: impl Into<String>, track_type: GadTrackType) -> &GadTrack {
        let id = format!("track_{}", self.tracks.len());
        let order = self.tracks.len() as u32;
        let mut track = GadTrack::new(id, name, track_type);
        track.order = order;
        self.tracks.push(track);
        self.dirty = true;
        self.tracks.last().unwrap()
    }

    /// Remove a track by ID.
    pub fn remove_track(&mut self, id: &str) -> bool {
        let before = self.tracks.len();
        self.tracks.retain(|t| t.id != id);
        if self.tracks.len() != before {
            self.dirty = true;
            // Reorder
            for (i, track) in self.tracks.iter_mut().enumerate() {
                track.order = i as u32;
            }
            true
        } else {
            false
        }
    }

    /// Get track by ID.
    pub fn track(&self, id: &str) -> Option<&GadTrack> {
        self.tracks.iter().find(|t| t.id == id)
    }

    /// Get mutable track by ID.
    pub fn track_mut(&mut self, id: &str) -> Option<&mut GadTrack> {
        self.dirty = true;
        self.tracks.iter_mut().find(|t| t.id == id)
    }

    /// Validate entire project.
    pub fn validate(&self) -> Vec<String> {
        let mut errors = Vec::new();
        if self.config.name.is_empty() {
            errors.push("Project name is empty".into());
        }
        if self.tracks.is_empty() {
            errors.push("No tracks in project".into());
        }
        for track in &self.tracks {
            let track_errors = track.validate();
            for e in track_errors {
                errors.push(format!("Track '{}': {}", track.name, e));
            }
        }
        // Check for unbound tracks (no event binding)
        let unbound: Vec<_> = self.tracks.iter()
            .filter(|t| t.metadata.event_binding.is_none())
            .map(|t| t.name.as_str())
            .collect();
        if !unbound.is_empty() {
            errors.push(format!("{} tracks have no event binding: {}",
                unbound.len(), unbound.join(", ")));
        }
        errors
    }

    /// Get track count by type.
    pub fn track_count_by_type(&self, tt: GadTrackType) -> usize {
        self.tracks.iter().filter(|t| t.track_type == tt).count()
    }

    /// Export project to JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }

    /// Import project from JSON.
    pub fn from_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_project() {
        let proj = GadProject::default_project();
        assert_eq!(proj.tracks.len(), 8); // 8 default tracks
        assert_eq!(proj.config.bpm, 120.0);
        assert_eq!(proj.config.sample_rate, 48000);
    }

    #[test]
    fn test_add_remove_track() {
        let mut proj = GadProject::default_project();
        let initial = proj.tracks.len();
        proj.add_track("Extra", GadTrackType::Transient);
        assert_eq!(proj.tracks.len(), initial + 1);
        assert!(proj.dirty);

        let last_id = proj.tracks.last().unwrap().id.clone();
        assert!(proj.remove_track(&last_id));
        assert_eq!(proj.tracks.len(), initial);
    }

    #[test]
    fn test_project_serialization_roundtrip() {
        let proj = GadProject::default_project();
        let json = proj.to_json().unwrap();
        let restored = GadProject::from_json(&json).unwrap();
        assert_eq!(restored.tracks.len(), proj.tracks.len());
        assert_eq!(restored.config.name, proj.config.name);
    }

    #[test]
    fn test_validation_unbound_tracks() {
        let proj = GadProject::default_project();
        let errors = proj.validate();
        // All default tracks have no event binding
        assert!(errors.iter().any(|e| e.contains("no event binding")));
    }
}
