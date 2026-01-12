//! App Preferences System
//!
//! Persistent user preferences for FluxForge Studio DAW:
//! - Audio settings (default sample rate, buffer size)
//! - UI preferences (theme, colors, zoom levels)
//! - Recent projects list
//! - Window state (position, size)
//! - Keyboard shortcuts customization

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

/// Maximum number of recent projects to track
const MAX_RECENT_PROJECTS: usize = 20;

/// Application preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AppPreferences {
    /// Audio settings
    pub audio: AudioPreferences,
    /// UI/Display settings
    pub ui: UiPreferences,
    /// Editor preferences
    pub editor: EditorPreferences,
    /// Recording preferences
    pub recording: RecordingPreferences,
    /// Recent projects list (most recent first)
    pub recent_projects: Vec<String>,
    /// Window state
    pub window: WindowState,
}

impl Default for AppPreferences {
    fn default() -> Self {
        Self {
            audio: AudioPreferences::default(),
            ui: UiPreferences::default(),
            editor: EditorPreferences::default(),
            recording: RecordingPreferences::default(),
            recent_projects: Vec::new(),
            window: WindowState::default(),
        }
    }
}

/// Audio preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioPreferences {
    /// Default sample rate (Hz)
    pub default_sample_rate: u32,
    /// Default buffer size (samples)
    pub default_buffer_size: u32,
    /// Preferred audio device name
    pub preferred_device: Option<String>,
    /// Enable low-latency mode
    pub low_latency: bool,
    /// Auto-connect to last device on startup
    pub auto_connect: bool,
}

impl Default for AudioPreferences {
    fn default() -> Self {
        Self {
            default_sample_rate: 48000,
            default_buffer_size: 256,
            preferred_device: None,
            low_latency: true,
            auto_connect: true,
        }
    }
}

/// UI preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct UiPreferences {
    /// Color theme (dark, light, custom)
    pub theme: String,
    /// Timeline zoom level (pixels per second)
    pub timeline_zoom: f64,
    /// Vertical track height (pixels)
    pub track_height: u32,
    /// Show track meters
    pub show_meters: bool,
    /// Show waveforms
    pub show_waveforms: bool,
    /// Show automation lanes
    pub show_automation: bool,
    /// Mixer view mode (compact, normal, large)
    pub mixer_view: String,
    /// Snap to grid by default
    pub snap_enabled: bool,
    /// Grid size in beats
    pub grid_beats: f64,
}

impl Default for UiPreferences {
    fn default() -> Self {
        Self {
            theme: "dark".to_string(),
            timeline_zoom: 100.0,
            track_height: 80,
            show_meters: true,
            show_waveforms: true,
            show_automation: false,
            mixer_view: "normal".to_string(),
            snap_enabled: true,
            grid_beats: 0.25, // 1/4 beat
        }
    }
}

/// Editor preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct EditorPreferences {
    /// Auto-save interval (seconds, 0 = disabled)
    pub autosave_interval: u32,
    /// Create backup before save
    pub backup_on_save: bool,
    /// Maximum undo history size
    pub max_undo_history: usize,
    /// Confirm before delete
    pub confirm_delete: bool,
    /// Auto-scroll during playback
    pub auto_scroll: bool,
    /// Follow playhead in timeline
    pub follow_playhead: bool,
}

impl Default for EditorPreferences {
    fn default() -> Self {
        Self {
            autosave_interval: 120, // 2 minutes
            backup_on_save: true,
            max_undo_history: 500,
            confirm_delete: true,
            auto_scroll: true,
            follow_playhead: true,
        }
    }
}

/// Recording preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct RecordingPreferences {
    /// Default recording format (wav, flac)
    pub format: String,
    /// Default bit depth (16, 24, 32)
    pub bit_depth: u32,
    /// Pre-roll time (beats)
    pub pre_roll: f64,
    /// Post-roll time (beats)
    pub post_roll: f64,
    /// Count-in enabled
    pub count_in: bool,
    /// Count-in bars
    pub count_in_bars: u32,
    /// Metronome during recording
    pub metronome_record: bool,
    /// Metronome during playback
    pub metronome_playback: bool,
}

impl Default for RecordingPreferences {
    fn default() -> Self {
        Self {
            format: "wav".to_string(),
            bit_depth: 24,
            pre_roll: 0.0,
            post_roll: 0.0,
            count_in: true,
            count_in_bars: 1,
            metronome_record: true,
            metronome_playback: false,
        }
    }
}

/// Window state (position and size)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WindowState {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub maximized: bool,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            x: 100,
            y: 100,
            width: 1600,
            height: 900,
            maximized: false,
        }
    }
}

impl AppPreferences {
    /// Load preferences from standard location
    pub fn load() -> Self {
        Self::load_from(Self::default_path())
    }

    /// Load preferences from specified path
    pub fn load_from<P: AsRef<Path>>(path: P) -> Self {
        match fs::read_to_string(path) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    /// Save preferences to standard location
    pub fn save(&self) -> std::io::Result<()> {
        self.save_to(Self::default_path())
    }

    /// Save preferences to specified path
    pub fn save_to<P: AsRef<Path>>(&self, path: P) -> std::io::Result<()> {
        // Ensure parent directory exists
        if let Some(parent) = path.as_ref().parent() {
            fs::create_dir_all(parent)?;
        }

        let json = serde_json::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        fs::write(path, json)
    }

    /// Get default preferences file path
    pub fn default_path() -> PathBuf {
        let base = if cfg!(target_os = "macos") {
            dirs::home_dir()
                .map(|h| h.join("Library/Application Support/FluxForge Studio"))
                .unwrap_or_else(|| PathBuf::from("."))
        } else if cfg!(target_os = "windows") {
            dirs::data_local_dir()
                .map(|d| d.join("FluxForge Studio"))
                .unwrap_or_else(|| PathBuf::from("."))
        } else {
            // Linux/other
            dirs::config_dir()
                .map(|d| d.join("fluxforge"))
                .unwrap_or_else(|| PathBuf::from("."))
        };
        base.join("preferences.json")
    }

    /// Add a project to recent projects list
    pub fn add_recent_project(&mut self, path: &str) {
        // Remove if already in list
        self.recent_projects.retain(|p| p != path);

        // Add to front
        self.recent_projects.insert(0, path.to_string());

        // Trim to max size
        if self.recent_projects.len() > MAX_RECENT_PROJECTS {
            self.recent_projects.truncate(MAX_RECENT_PROJECTS);
        }
    }

    /// Remove a project from recent projects list
    pub fn remove_recent_project(&mut self, path: &str) {
        self.recent_projects.retain(|p| p != path);
    }

    /// Clear all recent projects
    pub fn clear_recent_projects(&mut self) {
        self.recent_projects.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_preferences() {
        let prefs = AppPreferences::default();
        assert_eq!(prefs.audio.default_sample_rate, 48000);
        assert_eq!(prefs.audio.default_buffer_size, 256);
        assert!(prefs.recent_projects.is_empty());
    }

    #[test]
    fn test_recent_projects() {
        let mut prefs = AppPreferences::default();

        prefs.add_recent_project("/path/to/project1.rfp");
        prefs.add_recent_project("/path/to/project2.rfp");
        prefs.add_recent_project("/path/to/project3.rfp");

        assert_eq!(prefs.recent_projects.len(), 3);
        assert_eq!(prefs.recent_projects[0], "/path/to/project3.rfp");

        // Re-adding moves to front
        prefs.add_recent_project("/path/to/project1.rfp");
        assert_eq!(prefs.recent_projects[0], "/path/to/project1.rfp");
        assert_eq!(prefs.recent_projects.len(), 3);
    }

    #[test]
    fn test_serialization() {
        let prefs = AppPreferences::default();
        let json = serde_json::to_string(&prefs).unwrap();
        let loaded: AppPreferences = serde_json::from_str(&json).unwrap();
        assert_eq!(
            loaded.audio.default_sample_rate,
            prefs.audio.default_sample_rate
        );
    }
}
