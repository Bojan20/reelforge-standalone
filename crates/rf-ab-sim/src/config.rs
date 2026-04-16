//! Batch simulation configuration

use serde::{Deserialize, Serialize};
use rf_slot_lab::GameModel;

/// Audio event definition for simulation
/// Maps PAR stage names to voice/concurrent constraints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEventDef {
    /// Stage/event name (e.g. "WIN_3", "FREE_SPIN_TRIGGER")
    pub event_name: String,
    /// How many audio voices this event typically uses (1–8)
    #[serde(default = "default_voice_count")]
    pub voice_count: u32,
    /// Estimated audio duration in milliseconds
    #[serde(default = "default_duration_ms")]
    pub duration_ms: u32,
    /// Can overlap with itself (true) or must wait for previous to finish (false)
    #[serde(default = "default_true")]
    pub can_overlap: bool,
    /// Priority (1=lowest, 10=highest) — higher priority preempts lower
    #[serde(default = "default_priority")]
    pub priority: u8,
}

fn default_voice_count() -> u32 { 2 }
fn default_duration_ms() -> u32 { 1000 }
fn default_true() -> bool { true }
fn default_priority() -> u8 { 5 }

impl AudioEventDef {
    pub fn new(event_name: impl Into<String>) -> Self {
        Self {
            event_name: event_name.into(),
            voice_count: default_voice_count(),
            duration_ms: default_duration_ms(),
            can_overlap: true,
            priority: default_priority(),
        }
    }

    pub fn with_voices(mut self, count: u32) -> Self {
        self.voice_count = count;
        self
    }

    pub fn with_duration(mut self, ms: u32) -> Self {
        self.duration_ms = ms;
        self
    }

    pub fn non_overlapping(mut self) -> Self {
        self.can_overlap = false;
        self
    }
}

/// Player archetype — models different player session behaviors
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerArchetype {
    /// Archetype identifier
    pub id: String,
    /// Fraction of player sessions matching this archetype (0.0–1.0, sum must = 1.0)
    pub weight: f64,
    /// Average spin rate (spins per minute)
    #[serde(default = "default_spin_rate")]
    pub spin_rate_per_minute: f64,
    /// Auto-spin mode (no pause between spins)
    #[serde(default)]
    pub auto_spin: bool,
    /// Session length in spins
    #[serde(default = "default_session_spins")]
    pub session_spins: u32,
}

fn default_spin_rate() -> f64 { 40.0 }
fn default_session_spins() -> u32 { 200 }

impl PlayerArchetype {
    /// Casual player: slow, manual, short sessions
    pub fn casual() -> Self {
        Self {
            id: "casual".to_string(),
            weight: 0.5,
            spin_rate_per_minute: 25.0,
            auto_spin: false,
            session_spins: 100,
        }
    }

    /// Regular player: medium speed, mix of manual/auto
    pub fn regular() -> Self {
        Self {
            id: "regular".to_string(),
            weight: 0.35,
            spin_rate_per_minute: 40.0,
            auto_spin: false,
            session_spins: 300,
        }
    }

    /// Turbo player: max speed auto-spin
    pub fn turbo() -> Self {
        Self {
            id: "turbo".to_string(),
            weight: 0.15,
            spin_rate_per_minute: 120.0,
            auto_spin: true,
            session_spins: 1000,
        }
    }
}

impl PlayerBehavior for PlayerArchetype {
    fn ms_between_spins(&self) -> u64 {
        if self.spin_rate_per_minute <= 0.0 {
            return 1500;
        }
        (60_000.0 / self.spin_rate_per_minute) as u64
    }
}

/// Trait for computing spin timing
pub trait PlayerBehavior {
    fn ms_between_spins(&self) -> u64;
}

/// Full batch simulation configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchSimConfig {
    /// Game model to simulate (from PAR or GDD)
    pub game_model: GameModel,

    /// Total number of spins to simulate
    #[serde(default = "default_spin_count")]
    pub spin_count: u64,

    /// Audio event definitions (voice counts, durations)
    /// If empty, uses defaults based on win tier names
    #[serde(default)]
    pub audio_events: Vec<AudioEventDef>,

    /// Player archetypes for timing simulation
    /// If empty, uses standard mix
    #[serde(default)]
    pub player_archetypes: Vec<PlayerArchetype>,

    /// Number of parallel worker threads (0 = auto = num_cpus)
    #[serde(default)]
    pub threads: u8,

    /// Voice polyphony limit (default 48 for web, 64 for desktop)
    #[serde(default = "default_voice_budget")]
    pub voice_budget: u32,

    /// Random seed (None = random, Some(x) = deterministic)
    #[serde(default)]
    pub seed: Option<u64>,

    /// Timeline sample every N spins (0 = disable)
    #[serde(default = "default_timeline_sample_rate")]
    pub timeline_sample_rate: u32,

    /// Target RTP for validation (from PAR, 0.0 = skip)
    #[serde(default)]
    pub target_rtp: f64,
}

fn default_spin_count() -> u64 { 1_000_000 }
fn default_voice_budget() -> u32 { 48 }
fn default_timeline_sample_rate() -> u32 { 1000 }

impl Default for BatchSimConfig {
    fn default() -> Self {
        Self {
            game_model: GameModel::default(),
            spin_count: default_spin_count(),
            audio_events: Vec::new(),
            player_archetypes: Vec::new(),
            threads: 0,
            voice_budget: default_voice_budget(),
            seed: None,
            timeline_sample_rate: default_timeline_sample_rate(),
            target_rtp: 0.0,
        }
    }
}

impl BatchSimConfig {
    /// Create with default audio events based on win tier names from game model
    pub fn with_default_audio_events(mut self) -> Self {
        if self.audio_events.is_empty() {
            self.audio_events = default_audio_events_from_model(&self.game_model);
        }
        self
    }

    /// Create with standard player mix
    pub fn with_standard_player_mix(mut self) -> Self {
        if self.player_archetypes.is_empty() {
            self.player_archetypes = vec![
                PlayerArchetype::casual(),
                PlayerArchetype::regular(),
                PlayerArchetype::turbo(),
            ];
        }
        self
    }

    /// Get effective thread count
    pub fn effective_threads(&self) -> usize {
        if self.threads == 0 {
            num_cpus::get().min(16) // Cap at 16 to avoid memory pressure
        } else {
            self.threads as usize
        }
    }
}

/// Build default audio event defs from game model win tiers
fn default_audio_events_from_model(model: &GameModel) -> Vec<AudioEventDef> {
    use rf_slot_lab::WinTierConfig;

    let mut events = vec![
        AudioEventDef::new("SPIN_START").with_voices(1).with_duration(200),
        AudioEventDef::new("REEL_SPIN").with_voices(2).with_duration(1500),
        AudioEventDef::new("REEL_STOP").with_voices(1).with_duration(300),
        AudioEventDef::new("DEAD_SPIN").with_voices(1).with_duration(200),
        AudioEventDef::new("NEAR_MISS").with_voices(3).with_duration(800),
        AudioEventDef::new("WIN_LOW").with_voices(1).with_duration(500),
        AudioEventDef::new("WIN_EQUAL").with_voices(2).with_duration(600),
        AudioEventDef::new("WIN_1").with_voices(2).with_duration(800),
        AudioEventDef::new("WIN_2").with_voices(3).with_duration(1000),
        AudioEventDef::new("WIN_3").with_voices(4).with_duration(2000),
        AudioEventDef::new("WIN_4").with_voices(5).with_duration(3500),
        AudioEventDef::new("WIN_5").with_voices(6).with_duration(5000),
        AudioEventDef::new("BIG_WIN_START").with_voices(8).with_duration(6000).non_overlapping(),
        AudioEventDef::new("FREE_SPIN_TRIGGER").with_voices(6).with_duration(4000).non_overlapping(),
        AudioEventDef::new("FREE_SPIN_RETRIGGER").with_voices(5).with_duration(2000),
        AudioEventDef::new("JACKPOT").with_voices(8).with_duration(10000).non_overlapping(),
        AudioEventDef::new("ANTICIPATION").with_voices(3).with_duration(2000),
        AudioEventDef::new("SCATTER").with_voices(4).with_duration(1000),
    ];

    // Add feature-specific events from model
    for feature in &model.features {
        let event_name = format!("{}_TRIGGER", feature.id.to_uppercase());
        if !events.iter().any(|e| e.event_name == event_name) {
            events.push(
                AudioEventDef::new(event_name)
                    .with_voices(5)
                    .with_duration(3000)
                    .non_overlapping(),
            );
        }
    }

    events
}
