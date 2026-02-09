//! Context System
//!
//! Contexts represent distinct game chapters (BASE, FREESPINS, HOLDWIN, etc.)
//! Each context defines:
//! - Layers with audio tracks
//! - Entry/exit policies
//! - Audio character (tempo, key, energy)
//! - Constraints and narrative arc

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Context identifier (hash for RT comparison)
pub type ContextId = u32;

/// Layer identifier (0-based index)
pub type LayerId = u8;

/// Hash a context name for fast comparison
#[inline]
pub fn hash_context_id(name: &str) -> ContextId {
    let mut hash: u32 = 2166136261;
    for byte in name.bytes() {
        hash ^= byte as u32;
        hash = hash.wrapping_mul(16777619);
    }
    hash
}

/// Built-in context templates
pub mod templates {
    pub const BASE: &str = "BASE";
    pub const FREESPINS: &str = "FREESPINS";
    pub const HOLDWIN: &str = "HOLDWIN";
    pub const PICKEM: &str = "PICKEM";
    pub const WHEEL: &str = "WHEEL";
    pub const CASCADE: &str = "CASCADE";
    pub const JACKPOT: &str = "JACKPOT";
    pub const ANTICIPATION: &str = "ANTICIPATION";
}

/// Audio character for a context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioCharacter {
    /// Musical key (e.g., "E minor", "C major")
    #[serde(default)]
    pub key: String,
    /// Tempo in BPM
    #[serde(default = "default_tempo")]
    pub tempo_bpm: f32,
    /// Energy descriptor (e.g., "Epic Fantasy", "Ambient Mystical")
    #[serde(default)]
    pub energy: String,
    /// Time signature numerator
    #[serde(default = "default_time_sig_num")]
    pub time_sig_numerator: u8,
    /// Time signature denominator
    #[serde(default = "default_time_sig_denom")]
    pub time_sig_denominator: u8,
}

fn default_tempo() -> f32 {
    120.0
}
fn default_time_sig_num() -> u8 {
    4
}
fn default_time_sig_denom() -> u8 {
    4
}

impl Default for AudioCharacter {
    fn default() -> Self {
        Self {
            key: String::new(),
            tempo_bpm: 120.0,
            energy: String::new(),
            time_sig_numerator: 4,
            time_sig_denominator: 4,
        }
    }
}

impl AudioCharacter {
    /// Calculate beat duration in milliseconds
    pub fn beat_duration_ms(&self) -> f32 {
        60000.0 / self.tempo_bpm
    }

    /// Calculate bar duration in milliseconds
    pub fn bar_duration_ms(&self) -> f32 {
        self.beat_duration_ms() * self.time_sig_numerator as f32
    }
}

/// Audio track within a layer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayerTrack {
    /// Track identifier
    pub id: String,
    /// Audio file path (relative to project)
    pub path: String,
    /// Base volume (0.0 - 1.0)
    #[serde(default = "default_volume")]
    pub volume: f32,
    /// Pan position (-1.0 left to 1.0 right)
    #[serde(default)]
    pub pan: f32,
    /// Whether track should loop
    #[serde(default = "default_true")]
    pub looping: bool,
    /// Loop start position in samples
    #[serde(default)]
    pub loop_start: u64,
    /// Loop end position in samples (0 = end of file)
    #[serde(default)]
    pub loop_end: u64,
}

fn default_volume() -> f32 {
    1.0
}
fn default_true() -> bool {
    true
}

/// Layer definition (energy level)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Layer {
    /// Layer index (0 = L1, 4 = L5)
    pub index: LayerId,
    /// Human-readable name (e.g., "Ethereal", "Foundation", "Climax")
    pub name: String,
    /// Energy level (0.0 - 1.0)
    pub energy: f32,
    /// Tracks in this layer
    #[serde(default)]
    pub tracks: Vec<LayerTrack>,
}

impl Layer {
    /// Create a new layer
    pub fn new(index: LayerId, name: &str, energy: f32) -> Self {
        Self {
            index,
            name: name.to_string(),
            energy,
            tracks: Vec::new(),
        }
    }

    /// Add a track to this layer
    pub fn add_track(&mut self, track: LayerTrack) {
        self.tracks.push(track);
    }
}

/// Entry policy type
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum EntryPolicyType {
    /// Start at a fixed level
    #[default]
    Fixed,
    /// Map trigger to start level
    TriggerStrengthMapping,
    /// Inherit from previous context
    Inherit,
    /// Inherit momentum-adjusted level
    MomentumInherit,
}

/// Trigger to level mapping
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerMapping {
    /// Trigger identifier (e.g., "3_scatters", "retrigger")
    pub trigger: String,
    /// Target layer level
    pub level: LayerId,
    /// Transition profile to use
    #[serde(default)]
    pub transition: Option<String>,
}

/// Entry policy for a context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryPolicy {
    /// Policy type
    #[serde(default)]
    pub policy_type: EntryPolicyType,
    /// Default start level
    #[serde(default = "default_level")]
    pub default_level: LayerId,
    /// Whether to inherit momentum
    #[serde(default)]
    pub inherit_momentum: bool,
    /// Trigger to level mappings
    #[serde(default)]
    pub trigger_mappings: Vec<TriggerMapping>,
    /// Entry stinger audio path
    #[serde(default)]
    pub entry_stinger: Option<String>,
    /// Duck level for stinger (dB)
    #[serde(default)]
    pub stinger_duck_db: f32,
}

fn default_level() -> LayerId {
    1
}

impl Default for EntryPolicy {
    fn default() -> Self {
        Self {
            policy_type: EntryPolicyType::Fixed,
            default_level: 1,
            inherit_momentum: false,
            trigger_mappings: Vec::new(),
            entry_stinger: None,
            stinger_duck_db: -12.0,
        }
    }
}

impl EntryPolicy {
    /// Determine start level based on trigger
    pub fn resolve_start_level(&self, trigger: Option<&str>, current_level: LayerId) -> LayerId {
        if let Some(trig) = trigger {
            for mapping in &self.trigger_mappings {
                if mapping.trigger == trig {
                    return mapping.level;
                }
            }
        }

        match self.policy_type {
            EntryPolicyType::Fixed => self.default_level,
            EntryPolicyType::TriggerStrengthMapping => self.default_level,
            EntryPolicyType::Inherit | EntryPolicyType::MomentumInherit => current_level,
        }
    }
}

/// Wind-down configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindDown {
    /// Whether wind-down is enabled
    #[serde(default)]
    pub enabled: bool,
    /// Progress threshold to start wind-down (0.0-1.0)
    #[serde(default = "default_wind_down_start")]
    pub start_at_progress: f32,
    /// Target level during wind-down
    #[serde(default = "default_wind_down_level")]
    pub target_level: LayerId,
    /// Spins before exit to start wind-down
    #[serde(default = "default_spins_before_exit")]
    pub spins_before_exit: u32,
}

fn default_wind_down_start() -> f32 {
    0.9
}
fn default_wind_down_level() -> LayerId {
    2
}
fn default_spins_before_exit() -> u32 {
    2
}

impl Default for WindDown {
    fn default() -> Self {
        Self {
            enabled: true,
            start_at_progress: 0.9,
            target_level: 2,
            spins_before_exit: 2,
        }
    }
}

/// Summary stinger configuration (tiered by win result)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SummaryStinger {
    /// Small win stinger path
    #[serde(default)]
    pub small_win: Option<String>,
    /// Big win stinger path
    #[serde(default)]
    pub big_win: Option<String>,
    /// Mega win stinger path
    #[serde(default)]
    pub mega_win: Option<String>,
}

/// Exit policy for a context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExitPolicy {
    /// Context to return to
    #[serde(default = "default_return_context")]
    pub return_to: String,
    /// Level to return at
    #[serde(default = "default_level")]
    pub return_level: LayerId,
    /// Wind-down configuration
    #[serde(default)]
    pub wind_down: WindDown,
    /// Final transition profile
    #[serde(default)]
    pub final_transition: Option<String>,
    /// Fade duration in ms
    #[serde(default = "default_fade_duration")]
    pub fade_ms: u32,
    /// Overlap duration in ms
    #[serde(default = "default_overlap")]
    pub overlap_ms: u32,
    /// Summary stinger configuration
    #[serde(default)]
    pub summary_stinger: SummaryStinger,
}

fn default_return_context() -> String {
    templates::BASE.to_string()
}

fn default_fade_duration() -> u32 {
    2000
}

fn default_overlap() -> u32 {
    500
}

impl Default for ExitPolicy {
    fn default() -> Self {
        Self {
            return_to: templates::BASE.to_string(),
            return_level: 1,
            wind_down: WindDown::default(),
            final_transition: None,
            fade_ms: 2000,
            overlap_ms: 500,
            summary_stinger: SummaryStinger::default(),
        }
    }
}

/// Context constraints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextConstraints {
    /// Minimum allowed layer level
    #[serde(default)]
    pub min_level: LayerId,
    /// Maximum allowed layer level
    #[serde(default = "default_max_level")]
    pub max_level: LayerId,
    /// Cooldown between level changes (ms)
    #[serde(default = "default_level_cooldown")]
    pub level_change_cooldown_ms: u32,
    /// Maximum level changes per spin
    #[serde(default = "default_max_changes")]
    pub max_changes_per_spin: u32,
}

fn default_max_level() -> LayerId {
    4
}
fn default_level_cooldown() -> u32 {
    1500
}
fn default_max_changes() -> u32 {
    2
}

impl Default for ContextConstraints {
    fn default() -> Self {
        Self {
            min_level: 0,
            max_level: 4,
            level_change_cooldown_ms: 1500,
            max_changes_per_spin: 2,
        }
    }
}

/// Narrative arc type
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum NarrativeArcType {
    /// Build to climax
    BuildToClimax,
    /// Start high, wind down
    FrontLoaded,
    /// Maintain steady energy
    Sustained,
    /// Data-driven (rules control everything)
    #[default]
    DataDriven,
}

/// Narrative arc phase
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NarrativePhase {
    /// Phase name
    pub name: String,
    /// Start progress (0.0-1.0)
    pub start_progress: f32,
    /// End progress (0.0-1.0)
    pub end_progress: f32,
    /// Level bias (added to computed level)
    #[serde(default)]
    pub level_bias: i8,
    /// Minimum level during this phase
    #[serde(default)]
    pub min_level: Option<LayerId>,
    /// Maximum level during this phase
    #[serde(default)]
    pub max_level: Option<LayerId>,
}

/// Narrative arc configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NarrativeArc {
    /// Whether narrative arc is enabled
    #[serde(default)]
    pub enabled: bool,
    /// Arc type
    #[serde(default)]
    pub arc_type: NarrativeArcType,
    /// Custom phases (only for BuildToClimax/FrontLoaded)
    #[serde(default)]
    pub phases: Vec<NarrativePhase>,
}

impl Default for NarrativeArc {
    fn default() -> Self {
        Self {
            enabled: false,
            arc_type: NarrativeArcType::DataDriven,
            phases: Vec::new(),
        }
    }
}

impl NarrativeArc {
    /// Create a build-to-climax arc with standard phases
    pub fn build_to_climax() -> Self {
        Self {
            enabled: true,
            arc_type: NarrativeArcType::BuildToClimax,
            phases: vec![
                NarrativePhase {
                    name: "Opening".to_string(),
                    start_progress: 0.0,
                    end_progress: 0.3,
                    level_bias: 0,
                    min_level: None,
                    max_level: None,
                },
                NarrativePhase {
                    name: "Development".to_string(),
                    start_progress: 0.3,
                    end_progress: 0.7,
                    level_bias: 0,
                    min_level: None,
                    max_level: None,
                },
                NarrativePhase {
                    name: "Build".to_string(),
                    start_progress: 0.7,
                    end_progress: 0.9,
                    level_bias: 1,
                    min_level: Some(2),
                    max_level: None,
                },
                NarrativePhase {
                    name: "Climax".to_string(),
                    start_progress: 0.9,
                    end_progress: 1.0,
                    level_bias: 2,
                    min_level: Some(3),
                    max_level: None,
                },
            ],
        }
    }

    /// Get current phase based on progress
    pub fn get_phase(&self, progress: f32) -> Option<&NarrativePhase> {
        self.phases
            .iter()
            .find(|p| progress >= p.start_progress && progress < p.end_progress)
    }

    /// Apply narrative arc to a computed level
    pub fn apply(
        &self,
        level: LayerId,
        progress: f32,
        constraints: &ContextConstraints,
    ) -> LayerId {
        if !self.enabled {
            return level;
        }

        if let Some(phase) = self.get_phase(progress) {
            let biased = (level as i8 + phase.level_bias).clamp(0, 7) as LayerId;
            let min = phase.min_level.unwrap_or(constraints.min_level);
            let max = phase.max_level.unwrap_or(constraints.max_level);
            biased.clamp(min, max)
        } else {
            level
        }
    }
}

/// Complete context definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Context {
    /// Context identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Description
    #[serde(default)]
    pub description: String,
    /// Audio character
    #[serde(default)]
    pub audio_character: AudioCharacter,
    /// Layers (L1-L5)
    #[serde(default)]
    pub layers: Vec<Layer>,
    /// Entry policy
    #[serde(default)]
    pub entry_policy: EntryPolicy,
    /// Exit policy
    #[serde(default)]
    pub exit_policy: ExitPolicy,
    /// Constraints
    #[serde(default)]
    pub constraints: ContextConstraints,
    /// Narrative arc
    #[serde(default)]
    pub narrative_arc: NarrativeArc,
}

impl Context {
    /// Create a new context
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            description: String::new(),
            audio_character: AudioCharacter::default(),
            layers: Vec::new(),
            entry_policy: EntryPolicy::default(),
            exit_policy: ExitPolicy::default(),
            constraints: ContextConstraints::default(),
            narrative_arc: NarrativeArc::default(),
        }
    }

    /// Get context hash for RT comparison
    pub fn hash(&self) -> ContextId {
        hash_context_id(&self.id)
    }

    /// Add a layer
    pub fn add_layer(&mut self, layer: Layer) {
        self.layers.push(layer);
    }

    /// Get a layer by index
    pub fn get_layer(&self, index: LayerId) -> Option<&Layer> {
        self.layers.iter().find(|l| l.index == index)
    }

    /// Validate context configuration
    pub fn validate(&self) -> Result<(), String> {
        if self.id.is_empty() {
            return Err("Context ID cannot be empty".to_string());
        }
        if self.layers.is_empty() {
            return Err("Context must have at least one layer".to_string());
        }

        // Check layer indices are unique
        let mut seen = std::collections::HashSet::new();
        for layer in &self.layers {
            if !seen.insert(layer.index) {
                return Err(format!("Duplicate layer index: {}", layer.index));
            }
        }

        Ok(())
    }
}

/// Context registry
#[derive(Debug, Clone, Default)]
pub struct ContextRegistry {
    contexts: HashMap<String, Context>,
}

impl ContextRegistry {
    pub fn new() -> Self {
        Self {
            contexts: HashMap::new(),
        }
    }

    /// Register a context
    pub fn register(&mut self, context: Context) {
        self.contexts.insert(context.id.clone(), context);
    }

    /// Get a context by ID
    pub fn get(&self, id: &str) -> Option<&Context> {
        self.contexts.get(id)
    }

    /// Get a context by hash
    pub fn get_by_hash(&self, hash: ContextId) -> Option<&Context> {
        self.contexts.values().find(|c| c.hash() == hash)
    }

    /// Remove a context
    pub fn remove(&mut self, id: &str) -> Option<Context> {
        self.contexts.remove(id)
    }

    /// List all context IDs
    pub fn context_ids(&self) -> impl Iterator<Item = &str> {
        self.contexts.keys().map(|s| s.as_str())
    }

    /// Number of registered contexts
    pub fn len(&self) -> usize {
        self.contexts.len()
    }

    /// Check if registry is empty
    pub fn is_empty(&self) -> bool {
        self.contexts.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_context_hash() {
        assert_eq!(hash_context_id("BASE"), hash_context_id("BASE"));
        assert_ne!(hash_context_id("BASE"), hash_context_id("FREESPINS"));
    }

    #[test]
    fn test_audio_character_timing() {
        let char = AudioCharacter {
            tempo_bpm: 120.0,
            time_sig_numerator: 4,
            time_sig_denominator: 4,
            ..Default::default()
        };
        assert!((char.beat_duration_ms() - 500.0).abs() < 0.1);
        assert!((char.bar_duration_ms() - 2000.0).abs() < 0.1);
    }

    #[test]
    fn test_entry_policy_trigger_mapping() {
        let policy = EntryPolicy {
            trigger_mappings: vec![
                TriggerMapping {
                    trigger: "3_scatters".to_string(),
                    level: 1,
                    transition: None,
                },
                TriggerMapping {
                    trigger: "4_scatters".to_string(),
                    level: 2,
                    transition: None,
                },
            ],
            default_level: 0,
            ..Default::default()
        };

        assert_eq!(policy.resolve_start_level(Some("3_scatters"), 0), 1);
        assert_eq!(policy.resolve_start_level(Some("4_scatters"), 0), 2);
        assert_eq!(policy.resolve_start_level(Some("unknown"), 0), 0);
        assert_eq!(policy.resolve_start_level(None, 0), 0);
    }

    #[test]
    fn test_narrative_arc() {
        let arc = NarrativeArc::build_to_climax();
        let constraints = ContextConstraints::default();

        // Opening phase - no bias
        assert_eq!(arc.apply(1, 0.1, &constraints), 1);

        // Build phase - +1 bias, min L2
        assert_eq!(arc.apply(1, 0.8, &constraints), 2);

        // Climax phase - +2 bias, min L3
        assert_eq!(arc.apply(1, 0.95, &constraints), 3);
    }
}
