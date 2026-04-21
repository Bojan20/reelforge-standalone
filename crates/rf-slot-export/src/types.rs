//! Core export types — T3.1
//!
//! Shared data structures used by all export targets.

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT: FluxForge Export Project
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio event tier (importance level)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioTierExport {
    Subtle,
    Standard,
    Prominent,
    Flagship,
}

impl AudioTierExport {
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "flagship" => Self::Flagship,
            "prominent" => Self::Prominent,
            "standard" => Self::Standard,
            _ => Self::Subtle,
        }
    }

    pub fn priority(&self) -> u8 {
        match self {
            Self::Subtle => 3,
            Self::Standard => 5,
            Self::Prominent => 7,
            Self::Flagship => 10,
        }
    }
}

/// Event category for organizing output files
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioEventCategory {
    BaseGame,
    Win,
    NearMiss,
    Feature,
    Jackpot,
    Special,
    Ambient,
}

impl AudioEventCategory {
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "win" => Self::Win,
            "near_miss" | "nearmiss" => Self::NearMiss,
            "feature" => Self::Feature,
            "jackpot" => Self::Jackpot,
            "special" => Self::Special,
            "ambient" => Self::Ambient,
            _ => Self::BaseGame,
        }
    }

    /// Wwise/FMOD event bus grouping suggestion
    pub fn bus_path(&self) -> &'static str {
        match self {
            Self::BaseGame => "Master/SlotGame/BaseGame",
            Self::Win => "Master/SlotGame/Wins",
            Self::NearMiss => "Master/SlotGame/NearMiss",
            Self::Feature => "Master/SlotGame/Features",
            Self::Jackpot => "Master/SlotGame/Jackpot",
            Self::Special => "Master/SlotGame/Special",
            Self::Ambient => "Master/SlotGame/Ambient",
        }
    }
}

/// A single audio event definition for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEventExport {
    /// Stage name (e.g. "WIN_3", "FREE_SPIN_TRIGGER")
    pub name: String,
    /// Human-readable description
    pub description: String,
    /// Event category
    pub category: AudioEventCategory,
    /// Audio importance tier
    pub tier: AudioTierExport,
    /// Suggested duration in milliseconds
    pub duration_ms: u32,
    /// Suggested simultaneous voices
    pub voice_count: u8,
    /// Trigger probability per spin (0.0 = always / not applicable)
    pub trigger_probability: f64,
    /// Whether this event can overlap with itself
    pub can_overlap: bool,
    /// Whether this event loops (e.g. REEL_SPIN)
    pub can_loop: bool,
    /// Audio weight (0.0–1.0 fraction of total RTP)
    pub audio_weight: f64,
    /// Is this event required for regulatory compliance?
    pub is_required: bool,
    /// Priority (1–10). Derived from tier if not explicitly set.
    pub priority: u8,
    /// RTP contribution (fraction 0.0–1.0)
    pub rtp_contribution: f64,
}

impl AudioEventExport {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            description: String::new(),
            category: AudioEventCategory::BaseGame,
            tier: AudioTierExport::Standard,
            duration_ms: 1000,
            voice_count: 2,
            trigger_probability: 0.0,
            can_overlap: true,
            can_loop: false,
            audio_weight: 0.0,
            is_required: false,
            priority: 5,
            rtp_contribution: 0.0,
        }
    }

    /// Determine if this event should loop based on name heuristics
    pub fn should_loop(&self) -> bool {
        self.can_loop ||
        self.name.ends_with("_SPIN") ||
        self.name.contains("_AMBIENT") ||
        self.name.contains("_LOOP")
    }
}

/// Calibrated win tier for export (from T2.2 auto-calibration)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierExport {
    /// Tier ID (1=WIN_1, 2=WIN_2, etc.)
    pub tier_id: i32,
    /// Stage name (e.g. "WIN_3")
    pub stage_name: String,
    /// From multiplier (x-bet)
    pub from_multiplier: f64,
    /// To multiplier (x-bet)
    pub to_multiplier: f64,
    /// Rollup duration in milliseconds
    pub rollup_duration_ms: u32,
    /// Particle burst count
    pub particle_burst_count: u32,
}

/// Complete FluxForge project for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FluxForgeExportProject {
    /// Game display name
    pub game_name: String,
    /// Game identifier
    pub game_id: String,
    /// Target RTP (e.g. 96.50)
    pub rtp_target: f64,
    /// Volatility (LOW/MEDIUM/HIGH/VERY_HIGH)
    pub volatility: String,
    /// Maximum simultaneous voices
    pub voice_budget: u32,
    /// Grid dimensions
    pub reels: u8,
    pub rows: u8,
    /// Win mechanism description
    pub win_mechanism: String,
    /// All audio events
    pub audio_events: Vec<AudioEventExport>,
    /// Calibrated win tiers
    pub win_tiers: Vec<WinTierExport>,
    /// Export timestamp
    pub exported_at: String,
    /// FluxForge version
    pub tool_version: String,
}

impl FluxForgeExportProject {
    pub fn new(game_name: impl Into<String>, game_id: impl Into<String>) -> Self {
        Self {
            game_name: game_name.into(),
            game_id: game_id.into(),
            rtp_target: 0.0,
            volatility: "MEDIUM".to_string(),
            voice_budget: 48,
            reels: 5,
            rows: 3,
            win_mechanism: "paylines".to_string(),
            audio_events: Vec::new(),
            win_tiers: Vec::new(),
            exported_at: "".to_string(),
            tool_version: "FluxForge Studio 1.0".to_string(),
        }
    }

    /// Events by category
    pub fn events_by_category(&self, cat: &AudioEventCategory) -> Vec<&AudioEventExport> {
        self.audio_events.iter().filter(|e| &e.category == cat).collect()
    }

    /// Events by tier
    pub fn events_by_tier(&self, tier: &AudioTierExport) -> Vec<&AudioEventExport> {
        self.audio_events.iter().filter(|e| &e.tier == tier).collect()
    }

    /// Required events
    pub fn required_events(&self) -> Vec<&AudioEventExport> {
        self.audio_events.iter().filter(|e| e.is_required).collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT: Export Bundle
// ═══════════════════════════════════════════════════════════════════════════════

/// A single file in an export bundle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportFile {
    /// Filename (e.g. "golden_pantheon_audiosprite.json")
    pub filename: String,
    /// File content (UTF-8 text)
    pub content: String,
    /// MIME type (e.g. "application/json")
    pub mime_type: String,
    /// Optional: suggested output directory within the project
    pub suggested_path: Option<String>,
}

impl ExportFile {
    pub fn json(filename: impl Into<String>, content: impl Into<String>) -> Self {
        Self {
            filename: filename.into(),
            content: content.into(),
            mime_type: "application/json".to_string(),
            suggested_path: None,
        }
    }

    pub fn text(filename: impl Into<String>, content: impl Into<String>, mime: impl Into<String>) -> Self {
        Self {
            filename: filename.into(),
            content: content.into(),
            mime_type: mime.into(),
            suggested_path: None,
        }
    }

    pub fn with_path(mut self, path: impl Into<String>) -> Self {
        self.suggested_path = Some(path.into());
        self
    }
}

/// Complete export bundle from one export target
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportBundle {
    /// Format name (e.g. "Howler.js AudioSprite")
    pub format: String,
    /// Format version string
    pub version: String,
    /// All output files
    pub files: Vec<ExportFile>,
    /// Export warnings (informational)
    pub warnings: Vec<String>,
    /// Total event count exported
    pub event_count: usize,
}

impl ExportBundle {
    pub fn new(format: impl Into<String>, version: impl Into<String>) -> Self {
        Self {
            format: format.into(),
            version: version.into(),
            files: Vec::new(),
            warnings: Vec::new(),
            event_count: 0,
        }
    }

    pub fn add_file(mut self, file: ExportFile) -> Self {
        self.files.push(file);
        self
    }

    pub fn add_warning(mut self, warning: impl Into<String>) -> Self {
        self.warnings.push(warning.into());
        self
    }

    pub fn with_event_count(mut self, count: usize) -> Self {
        self.event_count = count;
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT TARGET TRAIT
// ═══════════════════════════════════════════════════════════════════════════════

/// Export errors
#[derive(Debug, thiserror::Error)]
pub enum ExportError {
    #[error("Serialization error: {0}")]
    Serialization(String),
    #[error("Empty project: no audio events to export")]
    EmptyProject,
    #[error("Invalid event definition: {0}")]
    InvalidEvent(String),
    #[error("Format-specific error: {0}")]
    FormatError(String),
}

/// Export target trait — implemented by each format-specific exporter
pub trait ExportTarget {
    /// Export the project to this target format.
    fn export(&self, project: &FluxForgeExportProject) -> Result<ExportBundle, ExportError>;

    /// Human-readable format name
    fn format_name(&self) -> &'static str;

    /// Format version string
    fn format_version(&self) -> &'static str;

    /// File extension hint for primary output file
    fn primary_extension(&self) -> &'static str;
}
