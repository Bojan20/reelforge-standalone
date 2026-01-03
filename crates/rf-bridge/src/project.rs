//! Project management utilities

use crate::{EngineBridge, ENGINE};
use rf_state::{Project, ProjectFormat};
use std::path::Path;

impl EngineBridge {
    /// Create a new empty project
    pub fn project_new(&mut self, name: &str) {
        self.project = Project::new(name);
        self.transport.position_samples = 0;
        self.transport.position_seconds = 0.0;
        self.transport.is_playing = false;
        self.transport.is_recording = false;
    }

    /// Save project to file (auto-detects format from extension)
    pub fn project_save(&mut self, path: &Path) -> Result<(), String> {
        let format = ProjectFormat::from_extension(path);
        self.project.save(path, format)
            .map_err(|e| format!("Save error: {}", e))?;
        self.project.touch();
        Ok(())
    }

    /// Load project from file
    pub fn project_load(&mut self, path: &Path) -> Result<(), String> {
        self.project = Project::load(path)
            .map_err(|e| format!("Load error: {}", e))?;

        // Sync transport from project
        self.transport.tempo = self.project.tempo;
        self.transport.time_sig_num = self.project.time_sig_num as u32;
        self.transport.time_sig_denom = self.project.time_sig_denom as u32;
        self.transport.loop_enabled = self.project.loop_enabled;
        self.transport.loop_start = self.project.loop_start as f64 / self.config.sample_rate.as_f64();
        self.transport.loop_end = self.project.loop_end as f64 / self.config.sample_rate.as_f64();

        // Reset playhead
        self.transport.position_samples = self.project.playhead;
        self.transport.position_seconds = self.project.playhead as f64 / self.config.sample_rate.as_f64();
        self.transport.is_playing = false;
        self.transport.is_recording = false;

        Ok(())
    }

    /// Get project name
    pub fn project_name(&self) -> &str {
        &self.project.meta.name
    }

    /// Set project name
    pub fn project_set_name(&mut self, name: &str) {
        self.project.meta.name = name.to_string();
        self.project.touch();
    }

    /// Get project tempo
    pub fn project_tempo(&self) -> f64 {
        self.project.tempo
    }

    /// Set project tempo
    pub fn project_set_tempo(&mut self, tempo: f64) {
        self.project.tempo = tempo.clamp(20.0, 999.0);
        self.transport.tempo = self.project.tempo;
        self.project.touch();
    }

    /// Get time signature
    pub fn project_time_signature(&self) -> (u8, u8) {
        (self.project.time_sig_num, self.project.time_sig_denom)
    }

    /// Set time signature
    pub fn project_set_time_signature(&mut self, num: u8, denom: u8) {
        self.project.time_sig_num = num;
        self.project.time_sig_denom = denom;
        self.transport.time_sig_num = num as u32;
        self.transport.time_sig_denom = denom as u32;
        self.project.touch();
    }
}

/// Export project info for Flutter
#[derive(Debug, Clone)]
pub struct ProjectInfo {
    pub name: String,
    pub author: Option<String>,
    pub track_count: usize,
    pub bus_count: usize,
    pub sample_rate: u32,
    pub tempo: f64,
    pub time_sig_num: u8,
    pub time_sig_denom: u8,
    pub duration_samples: u64,
    pub created_at: u64,
    pub modified_at: u64,
}

impl From<&EngineBridge> for ProjectInfo {
    fn from(bridge: &EngineBridge) -> Self {
        Self {
            name: bridge.project.meta.name.clone(),
            author: bridge.project.meta.author.clone(),
            track_count: bridge.project.tracks.len(),
            bus_count: bridge.project.buses.len(),
            sample_rate: bridge.config.sample_rate.as_u32(),
            tempo: bridge.project.tempo,
            time_sig_num: bridge.project.time_sig_num,
            time_sig_denom: bridge.project.time_sig_denom,
            duration_samples: bridge.project.meta.duration_samples,
            created_at: bridge.project.meta.created_at,
            modified_at: bridge.project.meta.modified_at,
        }
    }
}

/// Get current project info
pub fn get_project_info() -> Option<ProjectInfo> {
    let guard = ENGINE.read();
    guard.as_ref().map(ProjectInfo::from)
}
