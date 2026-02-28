//! GEG-4: Session Memory — SM factor in [0.7, 1.0].
//!
//! Tracks spin-based session history to modulate energy governance.
//! Three modifiers: loss streak softening, feature storm cooldown, jackpot compression.

use serde::{Deserialize, Serialize};

/// Session Memory factor. SM ∈ [0.7, 1.0].
///
/// SM = 1.0 means "fresh session, no modulation".
/// SM = 0.7 means "maximum session fatigue, energy compressed".
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMemory {
    /// Current SM value.
    sm: f64,
    /// Consecutive loss streak count.
    loss_streak: u32,
    /// Spins since last feature trigger.
    spins_since_feature: u32,
    /// Feature triggers in last N spins (rolling window).
    feature_count_window: u32,
    /// Window size for feature storm detection.
    feature_window_size: u32,
    /// Spins since last jackpot.
    spins_since_jackpot: u32,
    /// Whether jackpot compression is active.
    jackpot_compression_active: bool,
    /// Total spins in session.
    total_spins: u64,
}

impl Default for SessionMemory {
    fn default() -> Self {
        Self {
            sm: 1.0,
            loss_streak: 0,
            spins_since_feature: 0,
            feature_count_window: 0,
            feature_window_size: 20,
            spins_since_jackpot: 100,
            jackpot_compression_active: false,
            total_spins: 0,
        }
    }
}

impl SessionMemory {
    pub fn new() -> Self {
        Self::default()
    }

    /// Current SM factor.
    pub fn sm(&self) -> f64 {
        self.sm
    }

    /// Total spins tracked.
    pub fn total_spins(&self) -> u64 {
        self.total_spins
    }

    /// Current loss streak length.
    pub fn loss_streak(&self) -> u32 {
        self.loss_streak
    }

    /// Whether feature storm cooldown is active.
    pub fn feature_storm_active(&self) -> bool {
        self.feature_count_window >= 3
    }

    /// Whether jackpot compression is active.
    pub fn jackpot_compression_active(&self) -> bool {
        self.jackpot_compression_active
    }

    /// Reset to fresh session state.
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Record a spin result. Call after each spin.
    ///
    /// - `win_multiplier`: 0.0 = loss, > 0.0 = win (amount / bet)
    /// - `is_feature`: true if this spin triggered a bonus feature
    /// - `is_jackpot`: true if this spin hit a jackpot
    pub fn record_spin(&mut self, win_multiplier: f64, is_feature: bool, is_jackpot: bool) {
        self.total_spins += 1;
        self.spins_since_feature += 1;

        // ─── Loss streak tracking ───
        if win_multiplier <= 0.0 {
            self.loss_streak += 1;
        } else {
            self.loss_streak = 0;
        }

        // ─── Feature storm tracking ───
        if is_feature {
            self.feature_count_window += 1;
            self.spins_since_feature = 0;
        }
        // Decay feature count if no features in a while
        if self.spins_since_feature > self.feature_window_size && self.feature_count_window > 0 {
            self.feature_count_window = self.feature_count_window.saturating_sub(1);
        }

        // ─── Jackpot compression ───
        self.spins_since_jackpot += 1;
        if is_jackpot {
            self.jackpot_compression_active = true;
            self.spins_since_jackpot = 0;
        }
        // Jackpot compression decays after 30 spins
        if self.spins_since_jackpot > 30 {
            self.jackpot_compression_active = false;
        }

        // ─── Compute SM ───
        self.sm = self.compute_sm();
    }

    /// Compute the SM factor from current session state.
    fn compute_sm(&self) -> f64 {
        let mut sm = 1.0;

        // Loss streak softening: reduces SM as streak grows
        // 10+ consecutive losses → SM drops by up to 0.15
        if self.loss_streak > 5 {
            let loss_factor = ((self.loss_streak - 5) as f64 / 20.0).min(1.0);
            sm -= loss_factor * 0.15;
        }

        // Feature storm cooldown: rapid feature triggers compress energy
        // 3+ features in window → SM drops by up to 0.10
        if self.feature_count_window >= 3 {
            let storm_factor = ((self.feature_count_window - 2) as f64 / 5.0).min(1.0);
            sm -= storm_factor * 0.10;
        }

        // Jackpot compression: post-jackpot energy suppression
        // Drops SM by 0.05 immediately after jackpot, fades over 30 spins
        if self.jackpot_compression_active {
            let jp_fade = 1.0 - (self.spins_since_jackpot as f64 / 30.0).min(1.0);
            sm -= jp_fade * 0.05;
        }

        // Clamp to valid range
        sm.clamp(0.7, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fresh_session_sm_is_one() {
        let sm = SessionMemory::new();
        assert_eq!(sm.sm(), 1.0);
    }

    #[test]
    fn test_loss_streak_softening() {
        let mut sm = SessionMemory::new();
        // 25 consecutive losses
        for _ in 0..25 {
            sm.record_spin(0.0, false, false);
        }
        assert!(sm.sm() < 1.0, "Long loss streak should reduce SM: {}", sm.sm());
        assert!(sm.sm() >= 0.7, "SM should never go below 0.7: {}", sm.sm());
    }

    #[test]
    fn test_loss_streak_resets_on_win() {
        let mut sm = SessionMemory::new();
        for _ in 0..15 {
            sm.record_spin(0.0, false, false);
        }
        let sm_after_losses = sm.sm();
        assert!(sm_after_losses < 1.0);

        // Win resets streak
        sm.record_spin(5.0, false, false);
        assert_eq!(sm.loss_streak(), 0);
    }

    #[test]
    fn test_feature_storm_cooldown() {
        let mut sm = SessionMemory::new();
        // Trigger 5 features in rapid succession
        for _ in 0..5 {
            sm.record_spin(2.0, true, false);
        }
        assert!(sm.feature_storm_active());
        assert!(sm.sm() < 1.0, "Feature storm should reduce SM: {}", sm.sm());
    }

    #[test]
    fn test_jackpot_compression() {
        let mut sm = SessionMemory::new();
        sm.record_spin(100.0, false, true); // Jackpot!
        assert!(sm.jackpot_compression_active());
        assert!(sm.sm() < 1.0, "Jackpot should trigger compression: {}", sm.sm());

        // 31 spins later, compression should fade
        for _ in 0..31 {
            sm.record_spin(0.0, false, false);
        }
        assert!(!sm.jackpot_compression_active());
    }

    #[test]
    fn test_sm_never_below_minimum() {
        let mut sm = SessionMemory::new();
        // Worst case: long loss streak + feature storm + jackpot compression
        sm.record_spin(100.0, false, true); // Jackpot
        for _ in 0..5 {
            sm.record_spin(0.0, true, false); // Features during loss streak
        }
        for _ in 0..50 {
            sm.record_spin(0.0, false, false); // Long loss streak
        }
        assert!(sm.sm() >= 0.7, "SM must never go below 0.7: {}", sm.sm());
    }

    #[test]
    fn test_reset() {
        let mut sm = SessionMemory::new();
        for _ in 0..20 {
            sm.record_spin(0.0, false, false);
        }
        assert!(sm.sm() < 1.0);

        sm.reset();
        assert_eq!(sm.sm(), 1.0);
        assert_eq!(sm.total_spins(), 0);
        assert_eq!(sm.loss_streak(), 0);
    }

    #[test]
    fn test_determinism() {
        let mut a = SessionMemory::new();
        let mut b = SessionMemory::new();

        let spins = [(0.0, false, false), (5.0, true, false), (0.0, false, false),
                     (100.0, false, true), (0.0, false, false)];
        for (win, feat, jp) in &spins {
            a.record_spin(*win, *feat, *jp);
            b.record_spin(*win, *feat, *jp);
        }
        assert_eq!(a.sm(), b.sm());
    }
}
