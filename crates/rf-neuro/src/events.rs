//! Behavioral event types and sample structure.

use serde::{Deserialize, Serialize};

/// Result of a single spin
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpinOutcome {
    /// No win, no near-miss
    Loss,
    /// Very close to a winning combination (≥2 scatter symbols, 1 short)
    NearMiss,
    /// Small win (< 5× bet)
    SmallWin,
    /// Medium win (5–20× bet)
    MediumWin,
    /// Big win (20–50× bet)
    BigWin,
    /// Mega/epic win (> 50× bet)
    MegaWin,
    /// Bonus feature triggered (free spins, pick bonus, etc.)
    FeatureTriggered,
}

impl SpinOutcome {
    /// Win magnitude as a 0.0–1.0 score for signal processing
    pub fn win_score(self) -> f64 {
        match self {
            SpinOutcome::Loss => 0.0,
            SpinOutcome::NearMiss => 0.05,
            SpinOutcome::SmallWin => 0.2,
            SpinOutcome::MediumWin => 0.45,
            SpinOutcome::BigWin => 0.75,
            SpinOutcome::MegaWin => 1.0,
            SpinOutcome::FeatureTriggered => 0.9,
        }
    }

    pub fn is_win(self) -> bool {
        !matches!(self, SpinOutcome::Loss | SpinOutcome::NearMiss)
    }

    pub fn is_near_miss(self) -> bool {
        matches!(self, SpinOutcome::NearMiss)
    }

    pub fn is_feature(self) -> bool {
        matches!(self, SpinOutcome::FeatureTriggered)
    }
}

/// One observable player behavioral event
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "data", rename_all = "snake_case")]
pub enum BehavioralEvent {
    /// Player initiated spin (includes ms from last spin as inter-spin interval)
    SpinClick {
        /// Milliseconds since the previous spin (0 if first spin)
        inter_spin_ms: u64,
    },
    /// Reel stopped — result is known
    SpinResult {
        outcome: SpinOutcome,
        /// Win amount in credits (0 for loss/near-miss)
        win_credits: f64,
        /// Bet size in credits
        bet_credits: f64,
    },
    /// Player changed bet size
    BetChange {
        /// New bet in credits
        new_bet: f64,
        /// Previous bet in credits
        prev_bet: f64,
        /// True if changed after a loss
        after_loss: bool,
    },
    /// Player was inactive for this many ms (detected by the game)
    Pause {
        duration_ms: u64,
        /// True if last spin was a loss
        after_loss: bool,
    },
    /// Bonus feature started (free spins, etc.)
    FeatureStart {
        feature_name: String,
    },
    /// Bonus feature ended
    FeatureEnd {
        feature_name: String,
        total_win_credits: f64,
    },
    /// Player requested cashout (or partial cashout)
    CashOut {
        amount_credits: f64,
    },
    /// Player toggled autoplay
    AutoplayToggle {
        enabled: bool,
    },
    /// Player opened settings/paytable (mild disengagement signal)
    MenuOpen,
}

/// A timestamped behavioral observation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BehavioralSample {
    /// Milliseconds since session start (monotonically increasing)
    pub timestamp_ms: u64,
    /// What happened
    pub event: BehavioralEvent,
}

impl BehavioralSample {
    pub fn new(timestamp_ms: u64, event: BehavioralEvent) -> Self {
        Self { timestamp_ms, event }
    }

    pub fn spin_click(timestamp_ms: u64, inter_spin_ms: u64) -> Self {
        Self::new(timestamp_ms, BehavioralEvent::SpinClick { inter_spin_ms })
    }

    pub fn spin_result(timestamp_ms: u64, outcome: SpinOutcome, win: f64, bet: f64) -> Self {
        Self::new(timestamp_ms, BehavioralEvent::SpinResult {
            outcome,
            win_credits: win,
            bet_credits: bet,
        })
    }

    pub fn bet_change(timestamp_ms: u64, new_bet: f64, prev_bet: f64, after_loss: bool) -> Self {
        Self::new(timestamp_ms, BehavioralEvent::BetChange {
            new_bet,
            prev_bet,
            after_loss,
        })
    }

    pub fn pause(timestamp_ms: u64, duration_ms: u64, after_loss: bool) -> Self {
        Self::new(timestamp_ms, BehavioralEvent::Pause { duration_ms, after_loss })
    }
}
