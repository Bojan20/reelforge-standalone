//! Project Serialization System
//!
//! Provides robust project save/load with:
//! - Version migrations (v1, v2, v3...)
//! - Binary and JSON formats
//! - Compression support
//! - Asset embedding/linking
//! - Checksum validation

use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

// ============ Constants ============

/// Current project version for migrations
pub const PROJECT_VERSION: u32 = 2;

/// Magic bytes for binary format
const MAGIC_BYTES: &[u8; 4] = b"RFRG";

/// File extension
pub const PROJECT_EXTENSION: &str = "rfproj";

// ============ Project Metadata ============

/// Project metadata with enhanced fields
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMeta {
    /// Schema version
    pub version: u32,
    /// Project name
    pub name: String,
    /// Author name
    pub author: Option<String>,
    /// Description
    pub description: Option<String>,
    /// Creation timestamp (Unix ms)
    pub created_at: u64,
    /// Last modified timestamp (Unix ms)
    pub modified_at: u64,
    /// Duration in samples
    pub duration_samples: u64,
    /// Sample rate
    pub sample_rate: u32,
    /// Bit depth
    pub bit_depth: u8,
    /// Tags for organization
    pub tags: Vec<String>,
    /// Custom user metadata
    pub custom: HashMap<String, String>,
}

impl Default for ProjectMeta {
    fn default() -> Self {
        let now = current_timestamp();
        Self {
            version: PROJECT_VERSION,
            name: "Untitled Project".to_string(),
            author: None,
            description: None,
            created_at: now,
            modified_at: now,
            duration_samples: 0,
            sample_rate: 48000,
            bit_depth: 32,
            tags: Vec::new(),
            custom: HashMap::new(),
        }
    }
}

impl ProjectMeta {
    /// Update modified timestamp
    pub fn touch(&mut self) {
        self.modified_at = current_timestamp();
    }

    /// Duration in seconds
    pub fn duration_secs(&self) -> f64 {
        self.duration_samples as f64 / self.sample_rate as f64
    }
}

// ============ Bus State ============

/// Bus state for serialization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BusState {
    pub id: String,
    pub name: String,
    pub volume_db: f64,
    pub pan: f64,
    pub mute: bool,
    pub solo: bool,
    /// Insert effect chain (plugin IDs)
    pub inserts: Vec<InsertState>,
    /// Send levels to other buses
    pub sends: Vec<SendState>,
    /// Color for UI
    pub color: Option<u32>,
}

impl BusState {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            volume_db: 0.0,
            pan: 0.0,
            mute: false,
            solo: false,
            inserts: Vec::new(),
            sends: Vec::new(),
            color: None,
        }
    }
}

/// Insert effect state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsertState {
    pub slot: usize,
    pub plugin_id: String,
    pub bypassed: bool,
    pub mix: f64,
    pub parameters: HashMap<u32, f64>,
    pub preset_name: Option<String>,
}

/// Send state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendState {
    pub destination_id: String,
    pub level_db: f64,
    pub pan: f64,
    pub pre_fader: bool,
}

// ============ Master State ============

/// Master bus state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MasterState {
    pub volume_db: f64,
    pub limiter_enabled: bool,
    pub limiter_threshold_db: f64,
    pub limiter_release_ms: f64,
    pub dither_enabled: bool,
    pub dither_bits: u8,
    /// Master inserts
    pub inserts: Vec<InsertState>,
}

impl Default for MasterState {
    fn default() -> Self {
        Self {
            volume_db: 0.0,
            limiter_enabled: true,
            limiter_threshold_db: -0.3,
            limiter_release_ms: 100.0,
            dither_enabled: false,
            dither_bits: 24,
            inserts: Vec::new(),
        }
    }
}

// ============ Track State ============

/// Track type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrackType {
    Audio,
    Midi,
    Instrument,
    Bus,
    Master,
}

/// Track state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackState {
    pub id: String,
    pub name: String,
    pub track_type: TrackType,
    pub output_bus: String,
    pub volume_db: f64,
    pub pan: f64,
    pub mute: bool,
    pub solo: bool,
    pub armed: bool,
    pub color: Option<u32>,
    /// Regions/clips on this track
    pub regions: Vec<RegionState>,
    /// Automation lanes
    pub automation: Vec<AutomationLaneState>,
}

/// Audio region/clip state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegionState {
    pub id: String,
    pub name: String,
    /// Asset reference (file path or embedded ID)
    pub asset_ref: AssetRef,
    /// Start position in samples
    pub position: u64,
    /// Length in samples
    pub length: u64,
    /// Offset into source in samples
    pub source_offset: u64,
    /// Gain adjustment
    pub gain_db: f64,
    /// Fade in length (samples)
    pub fade_in: u64,
    /// Fade out length (samples)
    pub fade_out: u64,
    /// Locked (prevent editing)
    pub locked: bool,
}

/// Asset reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AssetRef {
    /// External file path (relative to project)
    External(PathBuf),
    /// Embedded asset ID
    Embedded(String),
    /// Missing/unresolved
    Missing(String),
}

/// Automation lane state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationLaneState {
    pub id: String,
    pub parameter_id: u32,
    pub parameter_name: String,
    pub points: Vec<AutomationPointState>,
    pub visible: bool,
}

/// Automation point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationPointState {
    pub position: u64,
    pub value: f64,
    pub curve_type: u8,
    pub tension: f64,
}

// Marker types moved to markers.rs
use crate::markers::MarkerTrack;

// ============ Complete Project ============

/// Complete project state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub meta: ProjectMeta,
    pub buses: Vec<BusState>,
    pub master: MasterState,
    pub tracks: Vec<TrackState>,
    pub marker_track: MarkerTrack,
    /// Embedded assets (audio data as base64 or raw bytes)
    #[serde(skip)]
    pub embedded_assets: HashMap<String, Vec<u8>>,
    /// Project tempo (BPM)
    pub tempo: f64,
    /// Time signature numerator
    pub time_sig_num: u8,
    /// Time signature denominator
    pub time_sig_denom: u8,
    /// Playhead position
    pub playhead: u64,
    /// Loop enabled
    pub loop_enabled: bool,
    /// Loop start
    pub loop_start: u64,
    /// Loop end
    pub loop_end: u64,
}

impl Default for Project {
    fn default() -> Self {
        Self {
            meta: ProjectMeta::default(),
            buses: vec![
                BusState::new("UI", "UI"),
                BusState::new("REELS", "Reels"),
                BusState::new("FX", "FX"),
                BusState::new("VO", "Voice Over"),
                BusState::new("MUSIC", "Music"),
                BusState::new("AMBIENT", "Ambient"),
            ],
            master: MasterState::default(),
            tracks: Vec::new(),
            marker_track: MarkerTrack::new(),
            embedded_assets: HashMap::new(),
            tempo: 120.0,
            time_sig_num: 4,
            time_sig_denom: 4,
            playhead: 0,
            loop_enabled: false,
            loop_start: 0,
            loop_end: 0,
        }
    }
}

impl Project {
    /// Create new project with name
    pub fn new(name: &str) -> Self {
        let mut project = Self::default();
        project.meta.name = name.to_string();
        project
    }

    /// Touch modified timestamp
    pub fn touch(&mut self) {
        self.meta.touch();
    }

    /// Calculate checksum
    pub fn checksum(&self) -> u32 {
        let json = serde_json::to_string(self).unwrap_or_default();
        crc32_hash(json.as_bytes())
    }

    // ---- JSON Format ----

    /// Serialize to pretty JSON
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    /// Deserialize from JSON
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    // ---- Save/Load ----

    /// Save project to file
    pub fn save(&self, path: &Path, format: ProjectFormat) -> Result<(), ProjectError> {
        // Ensure directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        match format {
            ProjectFormat::Json => self.save_json(path),
            ProjectFormat::Binary => self.save_binary(path),
            ProjectFormat::Compressed => self.save_compressed(path),
        }
    }

    fn save_json(&self, path: &Path) -> Result<(), ProjectError> {
        let json = self.to_json()?;
        std::fs::write(path, json)?;
        Ok(())
    }

    fn save_binary(&self, path: &Path) -> Result<(), ProjectError> {
        let mut file = std::fs::File::create(path)?;

        // Write magic bytes
        file.write_all(MAGIC_BYTES)?;

        // Write version
        file.write_all(&PROJECT_VERSION.to_le_bytes())?;

        // Write checksum
        let checksum = self.checksum();
        file.write_all(&checksum.to_le_bytes())?;

        // Write JSON payload
        let json = self.to_json()?;
        let json_bytes = json.as_bytes();
        file.write_all(&(json_bytes.len() as u64).to_le_bytes())?;
        file.write_all(json_bytes)?;

        // Write embedded assets
        file.write_all(&(self.embedded_assets.len() as u32).to_le_bytes())?;
        for (id, data) in &self.embedded_assets {
            let id_bytes = id.as_bytes();
            file.write_all(&(id_bytes.len() as u32).to_le_bytes())?;
            file.write_all(id_bytes)?;
            file.write_all(&(data.len() as u64).to_le_bytes())?;
            file.write_all(data)?;
        }

        Ok(())
    }

    fn save_compressed(&self, path: &Path) -> Result<(), ProjectError> {
        // For now, use JSON. Can add zstd/lz4 compression later
        self.save_json(path)
    }

    /// Maximum allowed project file size (100MB)
    /// Prevents DoS via maliciously large files
    const MAX_PROJECT_FILE_SIZE: u64 = 100 * 1024 * 1024;

    /// Load project from file
    pub fn load(path: &Path) -> Result<Self, ProjectError> {
        // Security: Check file size before loading
        let metadata = std::fs::metadata(path)?;
        if metadata.len() > Self::MAX_PROJECT_FILE_SIZE {
            return Err(ProjectError::Invalid(format!(
                "Project file too large: {} bytes (max {} bytes)",
                metadata.len(),
                Self::MAX_PROJECT_FILE_SIZE
            )));
        }

        // Detect format from file
        let mut file = std::fs::File::open(path)?;
        let mut magic = [0u8; 4];
        file.read_exact(&mut magic).ok();

        if &magic == MAGIC_BYTES {
            Self::load_binary(path)
        } else {
            Self::load_json(path)
        }
    }

    fn load_json(path: &Path) -> Result<Self, ProjectError> {
        let json = std::fs::read_to_string(path)?;
        let project = Self::from_json(&json)?;

        // Validate and migrate
        Self::validate_and_migrate(project)
    }

    fn load_binary(path: &Path) -> Result<Self, ProjectError> {
        let mut file = std::fs::File::open(path)?;

        // Read magic bytes
        let mut magic = [0u8; 4];
        file.read_exact(&mut magic)?;
        if &magic != MAGIC_BYTES {
            return Err(ProjectError::Invalid("Invalid file format".to_string()));
        }

        // Read version
        let mut version_bytes = [0u8; 4];
        file.read_exact(&mut version_bytes)?;
        let version = u32::from_le_bytes(version_bytes);

        if version > PROJECT_VERSION {
            return Err(ProjectError::FutureVersion(version));
        }

        // Read checksum
        let mut checksum_bytes = [0u8; 4];
        file.read_exact(&mut checksum_bytes)?;
        let stored_checksum = u32::from_le_bytes(checksum_bytes);

        // Read JSON payload length
        let mut len_bytes = [0u8; 8];
        file.read_exact(&mut len_bytes)?;
        let json_len = u64::from_le_bytes(len_bytes) as usize;

        // Security: Validate JSON payload size
        if json_len > Self::MAX_PROJECT_FILE_SIZE as usize {
            return Err(ProjectError::Invalid(format!(
                "JSON payload too large: {} bytes (max {} bytes)",
                json_len,
                Self::MAX_PROJECT_FILE_SIZE
            )));
        }

        // Read JSON
        let mut json_bytes = vec![0u8; json_len];
        file.read_exact(&mut json_bytes)?;
        let json = String::from_utf8(json_bytes)
            .map_err(|_| ProjectError::Invalid("Invalid UTF-8 in project".to_string()))?;

        let mut project: Project = serde_json::from_str(&json)?;

        // Verify checksum
        let computed_checksum = project.checksum();
        if stored_checksum != computed_checksum {
            log::warn!(
                "Checksum mismatch: stored={}, computed={}",
                stored_checksum,
                computed_checksum
            );
        }

        // Read embedded assets
        let mut asset_count_bytes = [0u8; 4];
        if file.read_exact(&mut asset_count_bytes).is_ok() {
            let asset_count = u32::from_le_bytes(asset_count_bytes) as usize;

            for _ in 0..asset_count {
                // Read asset ID
                let mut id_len_bytes = [0u8; 4];
                file.read_exact(&mut id_len_bytes)?;
                let id_len = u32::from_le_bytes(id_len_bytes) as usize;

                let mut id_bytes = vec![0u8; id_len];
                file.read_exact(&mut id_bytes)?;
                let id = String::from_utf8(id_bytes)
                    .map_err(|_| ProjectError::Invalid("Invalid asset ID".to_string()))?;

                // Read asset data
                let mut data_len_bytes = [0u8; 8];
                file.read_exact(&mut data_len_bytes)?;
                let data_len = u64::from_le_bytes(data_len_bytes) as usize;

                let mut data = vec![0u8; data_len];
                file.read_exact(&mut data)?;

                project.embedded_assets.insert(id, data);
            }
        }

        Self::validate_and_migrate(project)
    }

    /// Maximum allowed number of tracks (prevents DoS)
    const MAX_TRACKS: usize = 1000;
    /// Maximum allowed number of clips per track
    const MAX_CLIPS_PER_TRACK: usize = 10000;
    /// Maximum allowed number of markers
    const MAX_MARKERS: usize = 10000;
    /// Maximum allowed embedded assets
    const MAX_EMBEDDED_ASSETS: usize = 1000;

    /// Validate and migrate project
    fn validate_and_migrate(mut project: Project) -> Result<Project, ProjectError> {
        // Security: Validate project size limits to prevent DoS
        if project.tracks.len() > Self::MAX_TRACKS {
            return Err(ProjectError::Invalid(format!(
                "Too many tracks: {} (max {})",
                project.tracks.len(),
                Self::MAX_TRACKS
            )));
        }

        for (idx, track) in project.tracks.iter().enumerate() {
            if track.regions.len() > Self::MAX_CLIPS_PER_TRACK {
                return Err(ProjectError::Invalid(format!(
                    "Track {} has too many clips: {} (max {})",
                    idx,
                    track.regions.len(),
                    Self::MAX_CLIPS_PER_TRACK
                )));
            }
        }

        if project.marker_track.markers.len() > Self::MAX_MARKERS {
            return Err(ProjectError::Invalid(format!(
                "Too many markers: {} (max {})",
                project.marker_track.markers.len(),
                Self::MAX_MARKERS
            )));
        }

        if project.embedded_assets.len() > Self::MAX_EMBEDDED_ASSETS {
            return Err(ProjectError::Invalid(format!(
                "Too many embedded assets: {} (max {})",
                project.embedded_assets.len(),
                Self::MAX_EMBEDDED_ASSETS
            )));
        }

        // Migrate from older versions
        if project.meta.version < PROJECT_VERSION {
            project = migrate_project(project)?;
        }

        Ok(project)
    }

    // ---- Asset Management ----

    /// Embed an external asset
    pub fn embed_asset(&mut self, path: &Path) -> Result<String, ProjectError> {
        let data = std::fs::read(path)?;
        let id = format!(
            "asset_{}",
            path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
        );
        self.embedded_assets.insert(id.clone(), data);
        Ok(id)
    }

    /// Get embedded asset data
    pub fn get_asset(&self, id: &str) -> Option<&[u8]> {
        self.embedded_assets.get(id).map(|v| v.as_slice())
    }

    /// List all asset references
    pub fn list_assets(&self) -> Vec<AssetRef> {
        let mut assets = Vec::new();

        for track in &self.tracks {
            for region in &track.regions {
                assets.push(region.asset_ref.clone());
            }
        }

        assets
    }

    /// Resolve missing assets
    pub fn resolve_missing_assets<F>(&mut self, resolver: F)
    where
        F: Fn(&str) -> Option<PathBuf>,
    {
        for track in &mut self.tracks {
            for region in &mut track.regions {
                if let AssetRef::Missing(name) = &region.asset_ref
                    && let Some(path) = resolver(name) {
                        region.asset_ref = AssetRef::External(path);
                    }
            }
        }
    }
}

// ============ Project Format ============

/// Project file format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProjectFormat {
    /// Human-readable JSON
    Json,
    /// Binary format with embedded assets
    Binary,
    /// Compressed binary
    Compressed,
}

impl ProjectFormat {
    pub fn from_extension(path: &Path) -> Self {
        match path.extension().and_then(|e| e.to_str()) {
            Some("rfproj") => Self::Json,
            Some("rfprojb") => Self::Binary,
            Some("rfprojz") => Self::Compressed,
            _ => Self::Json,
        }
    }
}

// ============ Migration ============

/// Migrate project from older version
fn migrate_project(mut project: Project) -> Result<Project, ProjectError> {
    // V1 -> V2 migration
    if project.meta.version == 1 {
        log::info!("Migrating project from v1 to v2");

        // V2 added tempo, time signature, loop
        // These fields have defaults, so nothing special needed

        project.meta.version = 2;
    }

    // Future migrations go here...

    Ok(project)
}

// ============ Errors ============

/// Project errors
#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialize(#[from] serde_json::Error),

    #[error("Project version {0} is newer than supported (max: {PROJECT_VERSION})")]
    FutureVersion(u32),

    #[error("Invalid project: {0}")]
    Invalid(String),

    #[error("Asset not found: {0}")]
    AssetNotFound(String),
}

// ============ Helpers ============

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Simple CRC32 hash
fn crc32_hash(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFFFFFF;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB88320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

// ============ Tests ============

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

    #[test]
    fn test_project_checksum() {
        let project = Project::new("Test");
        let checksum1 = project.checksum();
        let checksum2 = project.checksum();

        assert_eq!(checksum1, checksum2);

        let mut project2 = project.clone();
        project2.meta.name = "Different".to_string();
        let checksum3 = project2.checksum();

        assert_ne!(checksum1, checksum3);
    }

    #[test]
    fn test_crc32() {
        assert_eq!(crc32_hash(b"hello"), 0x3610A686);
        assert_eq!(crc32_hash(b""), 0x00000000);
    }

    #[test]
    fn test_project_format_detection() {
        assert_eq!(
            ProjectFormat::from_extension(Path::new("test.rfproj")),
            ProjectFormat::Json
        );
        assert_eq!(
            ProjectFormat::from_extension(Path::new("test.rfprojb")),
            ProjectFormat::Binary
        );
    }

    #[test]
    fn test_bus_state() {
        let bus = BusState::new("TEST", "Test Bus");
        assert_eq!(bus.id, "TEST");
        assert_eq!(bus.name, "Test Bus");
        assert_eq!(bus.volume_db, 0.0);
    }

    #[test]
    fn test_project_default() {
        let project = Project::default();
        assert_eq!(project.buses.len(), 6);
        assert_eq!(project.tempo, 120.0);
        assert_eq!(project.time_sig_num, 4);
    }
}
