//! Project save/load

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Project version for migrations
pub const PROJECT_VERSION: u32 = 1;

/// Project metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMeta {
    pub version: u32,
    pub name: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub created: String,
    pub modified: String,
    pub sample_rate: u32,
}

impl Default for ProjectMeta {
    fn default() -> Self {
        Self {
            version: PROJECT_VERSION,
            name: "Untitled Project".to_string(),
            author: None,
            description: None,
            created: "2025-01-01T00:00:00Z".to_string(),
            modified: "2025-01-01T00:00:00Z".to_string(),
            sample_rate: 48000,
        }
    }
}

/// Bus state for serialization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BusState {
    pub id: String,
    pub volume_db: f64,
    pub pan: f64,
    pub mute: bool,
    pub solo: bool,
}

/// Master bus state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MasterState {
    pub volume_db: f64,
    pub limiter_enabled: bool,
    pub limiter_threshold_db: f64,
}

impl Default for MasterState {
    fn default() -> Self {
        Self {
            volume_db: 0.0,
            limiter_enabled: true,
            limiter_threshold_db: -0.3,
        }
    }
}

/// Complete project state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub meta: ProjectMeta,
    pub buses: Vec<BusState>,
    pub master: MasterState,
    // Add more state as needed:
    // pub tracks: Vec<TrackState>,
    // pub automation: Vec<AutomationLane>,
    // pub markers: Vec<Marker>,
}

impl Default for Project {
    fn default() -> Self {
        Self {
            meta: ProjectMeta::default(),
            buses: vec![
                BusState { id: "UI".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
                BusState { id: "REELS".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
                BusState { id: "FX".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
                BusState { id: "VO".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
                BusState { id: "MUSIC".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
                BusState { id: "AMBIENT".to_string(), volume_db: 0.0, pan: 0.0, mute: false, solo: false },
            ],
            master: MasterState::default(),
        }
    }
}

impl Project {
    pub fn new(name: &str) -> Self {
        let mut project = Self::default();
        project.meta.name = name.to_string();
        project
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    pub fn save(&self, path: &PathBuf) -> Result<(), ProjectError> {
        let json = self.to_json().map_err(ProjectError::Serialize)?;

        // Ensure directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(ProjectError::Io)?;
        }

        std::fs::write(path, json).map_err(ProjectError::Io)?;

        Ok(())
    }

    pub fn load(path: &PathBuf) -> Result<Self, ProjectError> {
        let json = std::fs::read_to_string(path).map_err(ProjectError::Io)?;
        let project = Self::from_json(&json).map_err(ProjectError::Serialize)?;

        // Handle version migrations
        if project.meta.version > PROJECT_VERSION {
            return Err(ProjectError::FutureVersion(project.meta.version));
        }

        Ok(project)
    }
}

/// Project errors
#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialize(#[from] serde_json::Error),

    #[error("Project version {0} is newer than supported")]
    FutureVersion(u32),

    #[error("Invalid project: {0}")]
    Invalid(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_project_serialization() {
        let project = Project::new("Test Project");
        let json = project.to_json().unwrap();
        let loaded = Project::from_json(&json).unwrap();

        assert_eq!(project.meta.name, loaded.meta.name);
        assert_eq!(project.buses.len(), loaded.buses.len());
    }
}
