//! SlotBlueprint — the top-level definition of a complete slot game.
//!
//! A blueprint is the single source of truth for everything about a slot:
//! math configuration, stage flow, audio DNA, compliance profiles,
//! and visual metadata for the editor.
//!
//! Blueprints are JSON-serializable and designed for:
//! - Marketplace sharing
//! - Version-controlled diff & merge
//! - Hot-reload into a running game
//! - Cross-studio template inheritance

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use semver::Version;
use uuid::Uuid;

use crate::flow::StageFlow;

// ─── Jurisdiction profile ─────────────────────────────────────────────────────

/// Regulatory jurisdiction configuration.
/// Each jurisdiction can override compliance thresholds, display requirements, etc.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JurisdictionProfile {
    /// ISO country code or regulator code (e.g. "GB", "UKGC", "MT", "MGA", "SE")
    pub code: String,

    /// Human name
    pub name: String,

    /// Maximum spin speed (ms per spin, enforced by executor)
    pub min_spin_duration_ms: u32,

    /// Maximum theoretical RTP allowed
    pub max_rtp: f64,

    /// Minimum theoretical RTP required
    pub min_rtp: f64,

    /// Maximum single-spin win cap (as multiple of max bet, None = unlimited)
    pub win_cap_multiplier: Option<f64>,

    /// Near-miss audio must be identical to no-win audio
    pub near_miss_audio_parity: bool,

    /// Auto-play allowed
    pub autoplay_allowed: bool,

    /// Maximum autoplay rounds (None = unlimited)
    pub max_autoplay_rounds: Option<u32>,

    /// Buy-feature allowed
    pub buy_feature_allowed: bool,

    /// Gamble/double-or-nothing allowed
    pub gamble_allowed: bool,

    /// Session duration limit (minutes, None = no limit)
    pub session_limit_minutes: Option<u32>,

    /// Mandatory reality check interval (minutes, None = not required)
    pub reality_check_minutes: Option<u32>,

    /// Responsible gambling message required
    pub rg_message_required: bool,

    /// Custom jurisdiction-specific rules (key → value)
    pub custom_rules: std::collections::HashMap<String, serde_json::Value>,
}

impl JurisdictionProfile {
    /// UKGC profile (UK Gambling Commission)
    pub fn ukgc() -> Self {
        Self {
            code: "UKGC".to_string(),
            name: "United Kingdom Gambling Commission".to_string(),
            min_spin_duration_ms: 2500,
            max_rtp: 0.999,
            min_rtp: 0.94,
            win_cap_multiplier: Some(25000.0),
            near_miss_audio_parity: true,
            autoplay_allowed: false, // UKGC banned autoplay 2021
            max_autoplay_rounds: None,
            buy_feature_allowed: false, // banned in UK
            gamble_allowed: true,
            session_limit_minutes: None,
            reality_check_minutes: Some(60),
            rg_message_required: true,
            custom_rules: Default::default(),
        }
    }

    /// MGA profile (Malta Gaming Authority)
    pub fn mga() -> Self {
        Self {
            code: "MGA".to_string(),
            name: "Malta Gaming Authority".to_string(),
            min_spin_duration_ms: 2500,
            max_rtp: 0.999,
            min_rtp: 0.92,
            win_cap_multiplier: None,
            near_miss_audio_parity: false,
            autoplay_allowed: true,
            max_autoplay_rounds: None,
            buy_feature_allowed: true,
            gamble_allowed: true,
            session_limit_minutes: None,
            reality_check_minutes: None,
            rg_message_required: true,
            custom_rules: Default::default(),
        }
    }

    /// Swedish regulatory profile (Spelinspektionen)
    pub fn sweden() -> Self {
        Self {
            code: "SE".to_string(),
            name: "Spelinspektionen (Sweden)".to_string(),
            min_spin_duration_ms: 2500,
            max_rtp: 0.97,
            min_rtp: 0.90,
            win_cap_multiplier: Some(500.0),
            near_miss_audio_parity: true,
            autoplay_allowed: true,
            max_autoplay_rounds: Some(30),
            buy_feature_allowed: false,
            gamble_allowed: false,
            session_limit_minutes: Some(60),
            reality_check_minutes: Some(60),
            rg_message_required: true,
            custom_rules: Default::default(),
        }
    }

    /// Generic "permissive" profile (for development / testing)
    pub fn dev() -> Self {
        Self {
            code: "DEV".to_string(),
            name: "Development (No restrictions)".to_string(),
            min_spin_duration_ms: 0,
            max_rtp: 1.0,
            min_rtp: 0.0,
            win_cap_multiplier: None,
            near_miss_audio_parity: false,
            autoplay_allowed: true,
            max_autoplay_rounds: None,
            buy_feature_allowed: true,
            gamble_allowed: true,
            session_limit_minutes: None,
            reality_check_minutes: None,
            rg_message_required: false,
            custom_rules: Default::default(),
        }
    }
}

// ─── Reel configuration ───────────────────────────────────────────────────────

/// A single reel strip definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelStrip {
    /// Reel index (0-based)
    pub index: u8,
    /// Symbol IDs in order (wraps around)
    pub symbols: Vec<u32>,
    /// Weights for weighted random selection (None = uniform)
    pub weights: Option<Vec<f32>>,
    /// Feature-specific strip variant (e.g. "free_spins")
    pub variant: Option<String>,
}

impl ReelStrip {
    pub fn uniform(index: u8, symbols: Vec<u32>) -> Self {
        Self { index, symbols, weights: None, variant: None }
    }

    pub fn weighted(index: u8, symbols: Vec<u32>, weights: Vec<f32>) -> Self {
        Self { index, symbols, weights: Some(weights), variant: None }
    }

    pub fn for_feature(mut self, variant: impl Into<String>) -> Self {
        self.variant = Some(variant.into());
        self
    }
}

/// Symbol definition in the paytable
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub id: u32,
    pub name: String,
    /// Win multipliers by match count [1x, 2x, 3x, 4x, 5x] (0 = no win)
    pub pays: Vec<f64>,
    /// Is this a wild?
    pub is_wild: bool,
    /// Is this a scatter?
    pub is_scatter: bool,
    /// Is this a bonus symbol?
    pub is_bonus: bool,
    /// Can expand (expanding wild)?
    pub can_expand: bool,
    /// Custom metadata
    pub meta: serde_json::Value,
}

/// Complete math configuration for the slot.
/// This is the machine-readable version of the PAR sheet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathConfig {
    /// Target RTP (0.0-1.0)
    pub rtp_target: f64,
    /// Volatility index (1=low, 10=high)
    pub volatility: u8,
    /// Hit frequency (0.0-1.0)
    pub hit_frequency: f64,
    /// Number of reels
    pub reel_count: u8,
    /// Number of rows
    pub row_count: u8,
    /// Number of paylines (0 = ways-to-win)
    pub payline_count: u16,
    /// Reel strips per mode (key = mode name, value = strips per reel)
    pub reel_strips: std::collections::HashMap<String, Vec<ReelStrip>>,
    /// Symbol definitions
    pub symbols: Vec<Symbol>,
    /// Maximum payout cap (as multiple of bet, enforced by executor)
    pub max_payout: f64,
    /// Free spins count on trigger
    pub free_spins_count: u8,
    /// Free spins multiplier
    pub free_spins_multiplier: f64,
    /// Buy feature cost multiplier (as multiple of bet)
    pub buy_feature_cost: Option<f64>,
    /// Jackpot tiers (name → fixed amount or contribution rate)
    pub jackpots: std::collections::HashMap<String, JackpotConfig>,
    /// Custom math parameters (extensible for novel mechanics)
    pub custom: std::collections::HashMap<String, serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JackpotConfig {
    /// Fixed amount (Some) or progressive (None, driven by contribution_rate)
    pub fixed_amount: Option<f64>,
    /// Contribution rate from each bet (0.0-1.0)
    pub contribution_rate: Option<f64>,
    /// Seed amount for progressive jackpots
    pub seed_amount: Option<f64>,
    /// Minimum bet to qualify
    pub min_bet: Option<f64>,
}

impl MathConfig {
    /// Blank math config for use in templates
    pub fn empty(reels: u8, rows: u8) -> Self {
        Self {
            rtp_target: 0.96,
            volatility: 5,
            hit_frequency: 0.25,
            reel_count: reels,
            row_count: rows,
            payline_count: 0,
            reel_strips: Default::default(),
            symbols: Vec::new(),
            max_payout: 500.0, // Conservative default — respects SE cap; override per-market
            free_spins_count: 10,
            free_spins_multiplier: 1.0,
            buy_feature_cost: None,
            jackpots: Default::default(),
            custom: Default::default(),
        }
    }
}

// ─── Audio DNA ────────────────────────────────────────────────────────────────

/// The brand's sonic identity — applied across all slots using this blueprint.
/// Creates a recognizable audio signature while allowing per-slot variation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDna {
    /// Brand name (e.g. "VanVinkl", "Pragmatic", "Play'n GO")
    pub brand: String,

    /// Core BPM range for base game music [min, max]
    pub bpm_range: [f32; 2],

    /// Root key for all musical content (C, C#, D, ... B)
    pub root_key: String,

    /// Modal flavor (major, minor, dorian, pentatonic_major, pentatonic_minor, etc.)
    pub mode: String,

    /// Primary instrument palette (e.g. ["piano", "strings", "brass"])
    pub instruments: Vec<String>,

    /// Base game audio profile name (references HELIX asset pack)
    pub base_profile: String,

    /// Feature game audio profile name
    pub feature_profile: String,

    /// Win escalation profile (how audio intensity scales with win multiplier)
    pub win_escalation_profile: String,

    /// Per-region audio profile overrides (region_code → profile_name)
    pub regional_profiles: std::collections::HashMap<String, String>,

    /// Audio DNA version (bump this to invalidate cached audio across all titles)
    pub version: String,
}

impl Default for AudioDna {
    fn default() -> Self {
        Self {
            brand: "Default".to_string(),
            bpm_range: [90.0, 130.0],
            root_key: "C".to_string(),
            mode: "major".to_string(),
            instruments: vec!["piano".to_string(), "strings".to_string()],
            base_profile: "default_base".to_string(),
            feature_profile: "default_feature".to_string(),
            win_escalation_profile: "default_win".to_string(),
            regional_profiles: Default::default(),
            version: "1.0.0".to_string(),
        }
    }
}

// ─── Compliance config ────────────────────────────────────────────────────────

/// Blueprint-level compliance configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComplianceConfig {
    /// Active jurisdiction profiles
    pub jurisdictions: Vec<JurisdictionProfile>,

    /// Whether auto-compliance validation is enabled on blueprint load
    pub auto_validate: bool,

    /// Audit trail destination (None = no audit, Some(url) = HTTP POST)
    pub audit_endpoint: Option<String>,

    /// Include a machine-readable compliance manifest in export
    pub include_manifest: bool,
}

impl Default for ComplianceConfig {
    fn default() -> Self {
        Self {
            jurisdictions: vec![JurisdictionProfile::dev()],
            auto_validate: true,
            audit_endpoint: None,
            include_manifest: true,
        }
    }
}

// ─── Blueprint metadata ────────────────────────────────────────────────────────

/// Authoring and marketplace metadata for a blueprint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlueprintMeta {
    /// Globally unique ID for this blueprint
    pub id: Uuid,

    /// Human name of the slot title
    pub title: String,

    /// Short description (max 200 chars, used in Marketplace)
    pub description: String,

    /// Author or studio name
    pub author: String,

    /// Author/studio UUID for Marketplace attribution
    pub author_id: Option<Uuid>,

    /// Semantic version (follows semver: 1.0.0, 1.0.1, ...)
    pub version: Version,

    /// Blueprint creation timestamp
    pub created_at: DateTime<Utc>,

    /// Last modification timestamp
    pub updated_at: DateTime<Utc>,

    /// Parent blueprint this one inherits from (template ID)
    pub parent_id: Option<Uuid>,

    /// Which parent version this was forked from
    pub parent_version: Option<Version>,

    /// Feature tags for Marketplace search
    /// e.g. ["cascading", "megaways", "free_spins", "jackpot"]
    pub feature_tags: Vec<String>,

    /// Supported reel configurations summary (e.g. "5x3", "6x4", "variable")
    pub reel_config: String,

    /// Whether this blueprint is published on Marketplace
    pub marketplace_public: bool,

    /// License type ("proprietary", "mit", "cc-by-sa", etc.)
    pub license: String,

    /// Changelog entry for current version
    pub changelog: Option<String>,
}

impl BlueprintMeta {
    pub fn new(title: impl Into<String>, author: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            description: String::new(),
            author: author.into(),
            author_id: None,
            version: Version::new(1, 0, 0),
            created_at: now,
            updated_at: now,
            parent_id: None,
            parent_version: None,
            feature_tags: Vec::new(),
            reel_config: "5x3".to_string(),
            marketplace_public: false,
            license: "proprietary".to_string(),
            changelog: None,
        }
    }
}

// ─── SlotBlueprint ────────────────────────────────────────────────────────────

/// The complete, self-contained definition of a slot game.
///
/// This is the single file you store, share, version-control, and deploy.
/// Everything needed to recreate the game from scratch is here.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotBlueprint {
    /// Authoring and Marketplace metadata
    pub meta: BlueprintMeta,

    /// Math model (PAR sheet equivalent)
    pub math: MathConfig,

    /// The stage flow graph (complete game logic)
    pub flow: StageFlow,

    /// Audio DNA (brand sonic identity)
    pub audio_dna: AudioDna,

    /// Compliance configuration
    pub compliance: ComplianceConfig,

    /// Blueprint-level RTPC defaults
    /// (these are applied to the HELIX Bus when the blueprint loads)
    pub rtpc_defaults: std::collections::HashMap<String, f32>,

    /// Hot-reload capable? (if false, blueprint swap requires full restart)
    pub hot_reload: bool,

    /// Blueprint format version (for forward-compat parsing)
    pub format_version: String,
}

impl SlotBlueprint {
    /// Create a blueprint from its components
    pub fn new(
        meta: BlueprintMeta,
        math: MathConfig,
        flow: StageFlow,
    ) -> Self {
        Self {
            meta,
            math,
            flow,
            audio_dna: AudioDna::default(),
            compliance: ComplianceConfig::default(),
            rtpc_defaults: Default::default(),
            hot_reload: true,
            format_version: "1.0.0".to_string(),
        }
    }

    pub fn with_audio_dna(mut self, dna: AudioDna) -> Self {
        self.audio_dna = dna;
        self
    }

    pub fn with_compliance(mut self, compliance: ComplianceConfig) -> Self {
        self.compliance = compliance;
        self
    }

    pub fn with_rtpc(mut self, key: impl Into<String>, value: f32) -> Self {
        self.rtpc_defaults.insert(key.into(), value);
        self
    }

    /// Serialize to JSON (for storage, marketplace, hot-reload)
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    /// Deserialize from JSON
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Fingerprint (SHA256-like hash of the JSON) for change detection
    pub fn fingerprint(&self) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let json = self.to_json().unwrap_or_default();
        let mut hasher = DefaultHasher::new();
        json.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    }

    /// Check if this blueprint is compatible with a specific jurisdiction
    pub fn supports_jurisdiction(&self, code: &str) -> bool {
        self.compliance.jurisdictions.iter().any(|j| j.code == code)
    }

    /// Number of game phases (nodes)
    pub fn phase_count(&self) -> usize {
        self.flow.node_count()
    }
}
