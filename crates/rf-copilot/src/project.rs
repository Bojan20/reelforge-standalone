//! Input project representation for the Co-Pilot.

use serde::{Deserialize, Serialize};

/// Minimal representation of one audio event in the project
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEventSpec {
    pub name: String,
    pub category: String,      // "BaseGame", "Win", "Feature", "Jackpot", etc.
    pub tier: String,          // "subtle", "standard", "prominent", "flagship"
    pub duration_ms: u32,
    pub voice_count: u8,
    pub is_required: bool,
    pub can_loop: bool,
    pub trigger_probability: f64,
    pub audio_weight: f64,
    pub rtp_contribution: f64,
}

/// Minimal representation of the whole project for Co-Pilot analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioProjectSpec {
    pub game_name: String,
    pub game_id: String,
    pub rtp_target: f64,
    /// "LOW", "MEDIUM", "HIGH", "VERY_HIGH"
    pub volatility: String,
    /// Max polyphony budget
    pub voice_budget: u8,
    pub reels: u8,
    pub rows: u8,
    /// "5 reels 3 rows", "megaways", "243 ways", etc.
    pub win_mechanism: String,
    pub audio_events: Vec<AudioEventSpec>,
    /// Optional: estimated peak voice count from voice budget analysis
    pub estimated_peak_voices: Option<f64>,
}

impl AudioProjectSpec {
    pub fn event_count(&self) -> usize { self.audio_events.len() }

    pub fn events_by_category(&self, cat: &str) -> Vec<&AudioEventSpec> {
        self.audio_events.iter().filter(|e| e.category == cat).collect()
    }

    pub fn win_events(&self) -> Vec<&AudioEventSpec> {
        self.events_by_category("Win")
    }

    pub fn base_game_events(&self) -> Vec<&AudioEventSpec> {
        self.events_by_category("BaseGame")
    }

    pub fn feature_events(&self) -> Vec<&AudioEventSpec> {
        self.events_by_category("Feature")
    }

    pub fn jackpot_events(&self) -> Vec<&AudioEventSpec> {
        self.events_by_category("Jackpot")
    }

    pub fn has_event_containing(&self, fragment: &str) -> bool {
        self.audio_events.iter().any(|e| e.name.contains(fragment))
    }

    pub fn event_by_name(&self, name: &str) -> Option<&AudioEventSpec> {
        self.audio_events.iter().find(|e| e.name == name)
    }

    pub fn is_megaways(&self) -> bool {
        self.win_mechanism.to_lowercase().contains("megaways")
    }

    pub fn is_high_volatility(&self) -> bool {
        matches!(self.volatility.as_str(), "HIGH" | "VERY_HIGH")
    }

    pub fn is_jackpot_game(&self) -> bool {
        !self.jackpot_events().is_empty()
    }
}
