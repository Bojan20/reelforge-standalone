use serde::{Deserialize, Serialize};

use crate::collision::VoiceEntry;
use crate::geometry::ScreenEvent;

/// Complete runtime state of the AUREXIS engine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AurexisState {
    // ═══ INPUTS ═══
    /// Current volatility index (0.0 = low, 1.0 = extreme).
    pub volatility_index: f64,
    /// Current RTP percentage (85.0 - 99.5).
    pub rtp_percent: f64,

    // ═══ WIN STATE ═══
    /// Current win amount (currency units).
    pub win_amount: f64,
    /// Current bet amount.
    pub bet_amount: f64,
    /// Win-to-bet multiplier (derived: win_amount / bet_amount).
    pub win_multiplier: f64,
    /// Jackpot proximity (0.0 = far, 1.0 = imminent).
    pub jackpot_proximity: f64,

    // ═══ SESSION ═══
    /// Total elapsed session time (ms).
    pub session_elapsed_ms: u64,
    /// Current fatigue index (0.0 = fresh, 1.0 = fatigued).
    pub fatigue_index: f64,
    /// Current RMS level being fed (dB).
    pub current_rms_db: f64,
    /// Current HF energy being fed (dB).
    pub current_hf_db: f64,

    // ═══ VOICES ═══
    /// Active voices for collision tracking.
    #[serde(skip)]
    pub voices: Vec<VoiceEntry>,

    // ═══ SCREEN EVENTS ═══
    /// Active screen events for attention vector.
    #[serde(skip)]
    pub screen_events: Vec<ScreenEvent>,

    // ═══ VARIATION SEED ═══
    /// Seed components for deterministic variation.
    pub seed_sprite_id: u64,
    pub seed_event_time: u64,
    pub seed_game_state: u64,
    pub seed_session_index: u64,

    // ═══ INITIALIZED ═══
    pub initialized: bool,
}

impl Default for AurexisState {
    fn default() -> Self {
        Self {
            volatility_index: 0.5,
            rtp_percent: 96.0,
            win_amount: 0.0,
            bet_amount: 1.0,
            win_multiplier: 0.0,
            jackpot_proximity: 0.0,
            session_elapsed_ms: 0,
            fatigue_index: 0.0,
            current_rms_db: -60.0,
            current_hf_db: -60.0,
            voices: Vec::new(),
            screen_events: Vec::new(),
            seed_sprite_id: 0,
            seed_event_time: 0,
            seed_game_state: 0,
            seed_session_index: 0,
            initialized: false,
        }
    }
}

impl AurexisState {
    /// Reset session-specific state (fatigue, timing) without clearing config.
    pub fn reset_session(&mut self) {
        self.session_elapsed_ms = 0;
        self.fatigue_index = 0.0;
        self.current_rms_db = -60.0;
        self.current_hf_db = -60.0;
        self.win_amount = 0.0;
        self.win_multiplier = 0.0;
        self.jackpot_proximity = 0.0;
        self.voices.clear();
        self.screen_events.clear();
    }

    /// Update win data and compute multiplier.
    pub fn update_win(&mut self, amount: f64, bet: f64, jackpot_proximity: f64) {
        self.win_amount = amount;
        self.bet_amount = if bet > 0.0 { bet } else { 1.0 };
        self.win_multiplier = self.win_amount / self.bet_amount;
        self.jackpot_proximity = jackpot_proximity.clamp(0.0, 1.0);
    }
}
