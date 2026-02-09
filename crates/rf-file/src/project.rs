//! Project file serialization
//!
//! Handles:
//! - Project files (.rfproj)
//! - Session autosave
//! - Preset files

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{FileError, FileResult};

// ═══════════════════════════════════════════════════════════════════════════════
// PATH VALIDATION (SECURITY)
// ═══════════════════════════════════════════════════════════════════════════════

/// Maximum length for paths in project files (prevents DoS via huge strings)
const MAX_PATH_LENGTH: usize = 4096;

/// Validate that a path is safe to use in a project
///
/// SECURITY: Prevents path traversal attacks where malicious project files
/// could reference files outside the project directory (e.g., "../../etc/passwd").
///
/// Returns the validated path if safe, or an error if:
/// - Path contains ".." components (directory traversal)
/// - Path is absolute (should be relative to project)
/// - Path exceeds maximum length
/// - Path contains null bytes
fn validate_clip_path(path: &str) -> FileResult<&str> {
    // Check for null bytes (can truncate path in C FFI)
    if path.contains('\0') {
        return Err(FileError::ProjectError(
            "Invalid path: contains null bytes".to_string(),
        ));
    }

    // Check path length
    if path.len() > MAX_PATH_LENGTH {
        return Err(FileError::ProjectError(format!(
            "Path exceeds maximum length of {} bytes",
            MAX_PATH_LENGTH
        )));
    }

    let path_ref = Path::new(path);

    // Reject absolute paths - clips should be relative to project
    if path_ref.is_absolute() {
        return Err(FileError::ProjectError(
            "Absolute paths not allowed for clips - use paths relative to project".to_string(),
        ));
    }

    // Check for path traversal attacks
    for component in path_ref.components() {
        match component {
            std::path::Component::ParentDir => {
                return Err(FileError::ProjectError(
                    "Path traversal detected: '..' not allowed in clip paths".to_string(),
                ));
            }
            std::path::Component::Normal(s) => {
                // Also check for Windows-style traversal attempts
                if let Some(s_str) = s.to_str()
                    && s_str.starts_with("..")
                {
                    return Err(FileError::ProjectError(
                        "Path traversal detected".to_string(),
                    ));
                }
            }
            _ => {}
        }
    }

    Ok(path)
}

/// Validate all paths in a project file after loading
///
/// SECURITY: Called after deserializing a project to ensure no malicious
/// paths were embedded in the file.
fn validate_project_paths(project: &ProjectFile) -> FileResult<()> {
    // Validate all clip paths
    for clip in &project.clips {
        validate_clip_path(&clip.file_path).map_err(|e| {
            FileError::ProjectError(format!(
                "Invalid path in clip '{}' (id {}): {}",
                clip.name, clip.id, e
            ))
        })?;
    }

    // Validate string lengths to prevent DoS
    if project.name.len() > 1024 {
        return Err(FileError::ProjectError(
            "Project name exceeds maximum length".to_string(),
        ));
    }

    for track in &project.tracks {
        if track.name.len() > 1024 {
            return Err(FileError::ProjectError(format!(
                "Track name exceeds maximum length: {}",
                track.id
            )));
        }
    }

    for marker in &project.markers {
        if marker.name.len() > 1024 {
            return Err(FileError::ProjectError(format!(
                "Marker name exceeds maximum length: {}",
                marker.id
            )));
        }
    }

    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROJECT FILE FORMAT
// ═══════════════════════════════════════════════════════════════════════════════

/// Project file version
pub const PROJECT_VERSION: u32 = 1;

/// Project file header
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectHeader {
    /// Format version
    pub version: u32,
    /// Application name
    pub app_name: String,
    /// Application version
    pub app_version: String,
    /// Creation timestamp (Unix epoch)
    pub created_at: u64,
    /// Last modified timestamp
    pub modified_at: u64,
}

impl Default for ProjectHeader {
    fn default() -> Self {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            version: PROJECT_VERSION,
            app_name: "FluxForge Studio".to_string(),
            app_version: env!("CARGO_PKG_VERSION").to_string(),
            created_at: now,
            modified_at: now,
        }
    }
}

/// Audio settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioSettings {
    pub sample_rate: u32,
    pub buffer_size: u32,
    pub bit_depth: u32,
}

impl Default for AudioSettings {
    fn default() -> Self {
        Self {
            sample_rate: 48000,
            buffer_size: 256,
            bit_depth: 32,
        }
    }
}

/// Track reference in project
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackRef {
    /// Track ID
    pub id: u32,
    /// Track name
    pub name: String,
    /// Track color (hex)
    pub color: String,
    /// Volume (0.0 - 1.0+)
    pub volume: f64,
    /// Pan (-1.0 to 1.0)
    pub pan: f64,
    /// Mute state
    pub mute: bool,
    /// Solo state
    pub solo: bool,
    /// Insert effect chain IDs
    pub inserts: Vec<u32>,
    /// Send levels (send_id -> level)
    pub sends: HashMap<u32, f64>,
}

impl Default for TrackRef {
    fn default() -> Self {
        Self {
            id: 0,
            name: "Track".to_string(),
            color: "#4a9eff".to_string(),
            volume: 1.0,
            pan: 0.0,
            mute: false,
            solo: false,
            inserts: Vec::new(),
            sends: HashMap::new(),
        }
    }
}

/// Audio clip reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipRef {
    /// Clip ID
    pub id: u32,
    /// Track ID
    pub track_id: u32,
    /// Clip name
    pub name: String,
    /// Audio file path (relative to project)
    pub file_path: String,
    /// Start position in samples
    pub start_sample: u64,
    /// Length in samples
    pub length_samples: u64,
    /// Offset into audio file (for trimmed clips)
    pub file_offset: u64,
    /// Gain (0.0 - 1.0+)
    pub gain: f64,
    /// Fade in samples
    pub fade_in: u64,
    /// Fade out samples
    pub fade_out: u64,
}

/// Effect preset reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectRef {
    /// Effect ID
    pub id: u32,
    /// Effect type (e.g., "eq", "compressor")
    pub effect_type: String,
    /// Effect name/preset
    pub name: String,
    /// Bypass state
    pub bypass: bool,
    /// Parameters (key -> value)
    pub params: HashMap<String, f64>,
}

/// Master bus settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MasterSettings {
    /// Master volume
    pub volume: f64,
    /// Master inserts
    pub inserts: Vec<u32>,
    /// Limiter enabled
    pub limiter_enabled: bool,
    /// Limiter ceiling dB
    pub limiter_ceiling: f64,
}

impl Default for MasterSettings {
    fn default() -> Self {
        Self {
            volume: 1.0,
            inserts: Vec::new(),
            limiter_enabled: true,
            limiter_ceiling: -0.3,
        }
    }
}

/// Complete project file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectFile {
    /// Project header
    pub header: ProjectHeader,
    /// Project name
    pub name: String,
    /// Audio settings
    pub audio: AudioSettings,
    /// Tempo (BPM)
    pub tempo: f64,
    /// Time signature numerator
    pub time_sig_num: u32,
    /// Time signature denominator
    pub time_sig_denom: u32,
    /// Tracks
    pub tracks: Vec<TrackRef>,
    /// Audio clips
    pub clips: Vec<ClipRef>,
    /// Effects
    pub effects: Vec<EffectRef>,
    /// Master bus
    pub master: MasterSettings,
    /// Markers
    pub markers: Vec<Marker>,
}

/// Timeline marker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Marker {
    pub id: u32,
    pub name: String,
    pub position: u64,
    pub color: String,
}

impl Default for ProjectFile {
    fn default() -> Self {
        Self {
            header: ProjectHeader::default(),
            name: "Untitled Project".to_string(),
            audio: AudioSettings::default(),
            tempo: 120.0,
            time_sig_num: 4,
            time_sig_denom: 4,
            tracks: Vec::new(),
            clips: Vec::new(),
            effects: Vec::new(),
            master: MasterSettings::default(),
            markers: Vec::new(),
        }
    }
}

impl ProjectFile {
    /// Create new empty project
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            ..Default::default()
        }
    }

    /// Save project to file
    pub fn save<P: AsRef<Path>>(&mut self, path: P) -> FileResult<()> {
        // Update modified timestamp
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        self.header.modified_at = now;

        let json = serde_json::to_string_pretty(self)?;
        fs::write(path, json)?;
        Ok(())
    }

    /// Load project from file
    ///
    /// SECURITY: Validates all paths and string lengths after deserialization
    /// to prevent path traversal attacks and DoS via oversized strings.
    pub fn load<P: AsRef<Path>>(path: P) -> FileResult<Self> {
        let content = fs::read_to_string(path.as_ref())?;

        // SECURITY: Limit total file size to prevent DoS
        const MAX_PROJECT_SIZE: usize = 50 * 1024 * 1024; // 50 MB
        if content.len() > MAX_PROJECT_SIZE {
            return Err(FileError::ProjectError(format!(
                "Project file exceeds maximum size of {} MB",
                MAX_PROJECT_SIZE / (1024 * 1024)
            )));
        }

        let project: ProjectFile = serde_json::from_str(&content)?;

        // Version check
        if project.header.version > PROJECT_VERSION {
            return Err(FileError::ProjectError(format!(
                "Project version {} is newer than supported version {}",
                project.header.version, PROJECT_VERSION
            )));
        }

        // SECURITY: Validate all paths and string lengths
        validate_project_paths(&project)?;

        Ok(project)
    }

    /// Add a track
    pub fn add_track(&mut self, name: &str) -> u32 {
        let id = self.tracks.len() as u32;
        self.tracks.push(TrackRef {
            id,
            name: name.to_string(),
            ..Default::default()
        });
        id
    }

    /// Add a clip
    ///
    /// SECURITY: Validates the file path to prevent path traversal attacks.
    /// Returns Err if the path is invalid (absolute, contains "..", etc.)
    pub fn add_clip(
        &mut self,
        track_id: u32,
        file_path: &str,
        start_sample: u64,
    ) -> FileResult<u32> {
        // SECURITY: Validate path before adding
        validate_clip_path(file_path)?;

        let id = self.clips.len() as u32;
        self.clips.push(ClipRef {
            id,
            track_id,
            name: Path::new(file_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Clip")
                .to_string(),
            file_path: file_path.to_string(),
            start_sample,
            length_samples: 0, // Will be set when loading audio
            file_offset: 0,
            gain: 1.0,
            fade_in: 0,
            fade_out: 0,
        });
        Ok(id)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET FILES
// ═══════════════════════════════════════════════════════════════════════════════

/// Effect preset file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PresetFile {
    /// Preset name
    pub name: String,
    /// Effect type
    pub effect_type: String,
    /// Author
    pub author: String,
    /// Description
    pub description: String,
    /// Tags
    pub tags: Vec<String>,
    /// Parameters
    pub params: HashMap<String, f64>,
}

impl PresetFile {
    pub fn save<P: AsRef<Path>>(&self, path: P) -> FileResult<()> {
        let json = serde_json::to_string_pretty(self)?;
        fs::write(path, json)?;
        Ok(())
    }

    pub fn load<P: AsRef<Path>>(path: P) -> FileResult<Self> {
        let content = fs::read_to_string(path)?;
        let preset: PresetFile = serde_json::from_str(&content)?;
        Ok(preset)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOSAVE
// ═══════════════════════════════════════════════════════════════════════════════

/// Autosave manager
pub struct AutosaveManager {
    /// Autosave directory
    autosave_dir: PathBuf,
    /// Autosave interval in seconds
    interval_secs: u64,
    /// Maximum autosaves to keep
    max_autosaves: usize,
}

impl AutosaveManager {
    pub fn new(autosave_dir: PathBuf) -> Self {
        Self {
            autosave_dir,
            interval_secs: 60,
            max_autosaves: 10,
        }
    }

    /// Ensure autosave directory exists
    pub fn ensure_dir(&self) -> FileResult<()> {
        fs::create_dir_all(&self.autosave_dir)?;
        Ok(())
    }

    /// Save autosave
    pub fn save(&self, project: &mut ProjectFile) -> FileResult<PathBuf> {
        self.ensure_dir()?;

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let filename = format!("autosave_{}.rfproj", timestamp);
        let path = self.autosave_dir.join(&filename);

        project.save(&path)?;

        // Cleanup old autosaves
        self.cleanup()?;

        Ok(path)
    }

    /// List autosaves
    pub fn list(&self) -> FileResult<Vec<PathBuf>> {
        if !self.autosave_dir.exists() {
            return Ok(Vec::new());
        }

        let mut autosaves: Vec<PathBuf> = fs::read_dir(&self.autosave_dir)?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("rfproj"))
            .collect();

        // Sort by modification time (newest first)
        autosaves.sort_by(|a, b| {
            let time_a = fs::metadata(a).and_then(|m| m.modified()).ok();
            let time_b = fs::metadata(b).and_then(|m| m.modified()).ok();
            time_b.cmp(&time_a)
        });

        Ok(autosaves)
    }

    /// Cleanup old autosaves
    fn cleanup(&self) -> FileResult<()> {
        let autosaves = self.list()?;

        for path in autosaves.into_iter().skip(self.max_autosaves) {
            let _ = fs::remove_file(path);
        }

        Ok(())
    }

    /// Get latest autosave
    pub fn latest(&self) -> FileResult<Option<PathBuf>> {
        Ok(self.list()?.into_iter().next())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_project_creation() {
        let project = ProjectFile::new("Test Project");

        assert_eq!(project.name, "Test Project");
        assert_eq!(project.tempo, 120.0);
        assert!(project.tracks.is_empty());
    }

    #[test]
    fn test_add_track() {
        let mut project = ProjectFile::new("Test");
        let id = project.add_track("Drums");

        assert_eq!(id, 0);
        assert_eq!(project.tracks.len(), 1);
        assert_eq!(project.tracks[0].name, "Drums");
    }

    #[test]
    fn test_project_serialization() {
        let mut project = ProjectFile::new("Test");
        project.add_track("Drums");
        project.tempo = 140.0;

        let json = serde_json::to_string(&project).unwrap();
        let loaded: ProjectFile = serde_json::from_str(&json).unwrap();

        assert_eq!(loaded.name, "Test");
        assert_eq!(loaded.tempo, 140.0);
        assert_eq!(loaded.tracks.len(), 1);
    }

    #[test]
    fn test_preset_serialization() {
        let preset = PresetFile {
            name: "Warm EQ".to_string(),
            effect_type: "eq".to_string(),
            author: "VanVinkl".to_string(),
            description: "Warm EQ preset".to_string(),
            tags: vec!["warm".to_string(), "eq".to_string()],
            params: [("gain".to_string(), 1.5)].into_iter().collect(),
        };

        let json = serde_json::to_string(&preset).unwrap();
        let loaded: PresetFile = serde_json::from_str(&json).unwrap();

        assert_eq!(loaded.name, "Warm EQ");
        assert_eq!(loaded.params.get("gain"), Some(&1.5));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_valid_clip_path() {
        let mut project = ProjectFile::new("Test");
        project.add_track("Track 1");

        // Valid relative paths should work
        assert!(project.add_clip(0, "audio/drums.wav", 0).is_ok());
        assert!(project.add_clip(0, "samples/kick.wav", 48000).is_ok());
        assert!(project.add_clip(0, "vocals.wav", 96000).is_ok());
    }

    #[test]
    fn test_path_traversal_blocked() {
        let mut project = ProjectFile::new("Test");
        project.add_track("Track 1");

        // Path traversal attempts should fail
        assert!(project.add_clip(0, "../etc/passwd", 0).is_err());
        assert!(project.add_clip(0, "audio/../../../secret.txt", 0).is_err());
        assert!(
            project
                .add_clip(0, "..\\windows\\system32\\config", 0)
                .is_err()
        );
    }

    #[test]
    fn test_absolute_path_blocked() {
        let mut project = ProjectFile::new("Test");
        project.add_track("Track 1");

        // Absolute paths should fail
        assert!(project.add_clip(0, "/etc/passwd", 0).is_err());
        assert!(project.add_clip(0, "/Users/victim/secret.wav", 0).is_err());

        #[cfg(windows)]
        {
            assert!(
                project
                    .add_clip(0, "C:\\Windows\\System32\\config", 0)
                    .is_err()
            );
            assert!(
                project
                    .add_clip(0, "\\\\server\\share\\file.wav", 0)
                    .is_err()
            );
        }
    }

    #[test]
    fn test_null_byte_blocked() {
        let mut project = ProjectFile::new("Test");
        project.add_track("Track 1");

        // Null bytes should fail (C string truncation attack)
        assert!(project.add_clip(0, "audio.wav\0.txt", 0).is_err());
    }

    #[test]
    fn test_project_load_validates_paths() {
        // Create a malicious project JSON with path traversal
        let malicious_json = r##"{
            "header": {"version": 1, "app_name": "FluxForge", "app_version": "0.1.0", "created_at": 0, "modified_at": 0},
            "name": "Malicious Project",
            "audio": {"sample_rate": 48000, "buffer_size": 256, "bit_depth": 32},
            "tempo": 120.0,
            "time_sig_num": 4,
            "time_sig_denom": 4,
            "tracks": [{"id": 0, "name": "Track", "color": "#fff", "volume": 1.0, "pan": 0.0, "mute": false, "solo": false, "inserts": [], "sends": {}}],
            "clips": [{"id": 0, "track_id": 0, "name": "Evil", "file_path": "../../../etc/passwd", "start_sample": 0, "length_samples": 1000, "file_offset": 0, "gain": 1.0, "fade_in": 0, "fade_out": 0}],
            "effects": [],
            "master": {"volume": 1.0, "inserts": [], "limiter_enabled": true, "limiter_ceiling": -0.3},
            "markers": []
        }"##;

        // Write to temp file and try to load
        let temp_dir = std::env::temp_dir();
        let temp_file = temp_dir.join("malicious_test.rfproj");
        std::fs::write(&temp_file, malicious_json).unwrap();

        // Load should fail due to path traversal
        let result = ProjectFile::load(&temp_file);
        assert!(result.is_err());

        // Cleanup
        let _ = std::fs::remove_file(temp_file);
    }
}
