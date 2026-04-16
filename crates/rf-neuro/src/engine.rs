//! NeuroEngine — real-time player behavioral signal processor.
//!
//! Maintains a sliding-window history of behavioral samples and updates
//! the 8D Player State Vector after each event. All state transitions are
//! deterministic and based on signal history rather than wall-clock time.

use std::collections::VecDeque;
use serde::{Deserialize, Serialize};
use crate::events::{BehavioralEvent, BehavioralSample};
use crate::state::{AudioAdaptation, PlayerStateVector};

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────

/// NeuroEngine runtime configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NeuroConfig {
    /// Sliding window duration in ms (default: 300_000 = 5 minutes)
    pub window_ms: u64,
    /// Maximum samples in the window (prevents unbounded memory)
    pub max_samples: usize,
    /// Output smoothing coefficient 0.0 (no smooth) – 0.99 (very slow)
    /// Applied between consecutive state updates: new = α×old + (1−α)×raw
    pub smoothing: f64,
    /// Enable responsible gaming automatic interventions
    pub rg_mode_enabled: bool,
    /// Exponential decay half-life in seconds for signal weighting
    pub decay_half_life_s: f64,
}

impl Default for NeuroConfig {
    fn default() -> Self {
        Self {
            window_ms: 300_000,
            max_samples: 2_000,
            smoothing: 0.30,
            rg_mode_enabled: true,
            decay_half_life_s: 120.0,  // 2 minutes
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL ACCUMULATORS
// ─────────────────────────────────────────────────────────────────────────────

/// Timestamped scalar observation for decay-weighted averaging
#[derive(Clone)]
struct Observation {
    ts: u64,
    value: f64,
}

/// Windowed signal accumulator (decay-weighted mean)
struct SignalWindow {
    data: VecDeque<Observation>,
    max_len: usize,
}

impl SignalWindow {
    fn new(max_len: usize) -> Self {
        Self { data: VecDeque::with_capacity(max_len.min(256)), max_len }
    }

    fn push(&mut self, ts: u64, value: f64) {
        if self.data.len() >= self.max_len {
            self.data.pop_front();
        }
        self.data.push_back(Observation { ts, value });
    }

    /// Decay-weighted mean. `now_ms` is the current (latest) timestamp.
    fn weighted_mean(&self, now_ms: u64, half_life_ms: f64) -> f64 {
        if self.data.is_empty() { return 0.0; }
        let mut wsum = 0.0f64;
        let mut wtot = 0.0f64;
        for obs in &self.data {
            let age_s = (now_ms.saturating_sub(obs.ts)) as f64 / 1000.0;
            let w = (0.5f64).powf(age_s / (half_life_ms / 1000.0));
            wsum += obs.value * w;
            wtot += w;
        }
        if wtot > 0.0 { (wsum / wtot).clamp(0.0, 1.0) } else { 0.0 }
    }

    #[allow(dead_code)]
    fn len(&self) -> usize { self.data.len() }
    #[allow(dead_code)]
    fn is_empty(&self) -> bool { self.data.is_empty() }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEURO ENGINE
// ─────────────────────────────────────────────────────────────────────────────

/// Real-time NeuroAudio™ behavioral signal processor.
pub struct NeuroEngine {
    config: NeuroConfig,

    // ── Signal windows ────────────────────────────────────────────────────
    inter_spin_ms: SignalWindow,   // spin click intervals (ms, norm by 3000)
    win_scores:    SignalWindow,   // outcome win score 0.0–1.0
    near_miss_raw: SignalWindow,   // near-miss signal (0 or 1)
    bet_change:    SignalWindow,   // bet change direction (-1..1 normalized)
    pause_signal:  SignalWindow,   // pause frustration signal

    // ── Session counters ──────────────────────────────────────────────────
    total_spins: u64,
    session_start_ms: Option<u64>,
    consecutive_losses: u32,
    consecutive_wins: u32,
    in_feature: bool,

    // ── Smoothed output state ─────────────────────────────────────────────
    smoothed: PlayerStateVector,
    adaptation: AudioAdaptation,
}

impl NeuroEngine {
    pub fn new(config: NeuroConfig) -> Self {
        let max = config.max_samples;
        Self {
            config,
            inter_spin_ms: SignalWindow::new(max),
            win_scores:    SignalWindow::new(max),
            near_miss_raw: SignalWindow::new(max),
            bet_change:    SignalWindow::new(max),
            pause_signal:  SignalWindow::new(max),
            total_spins: 0,
            session_start_ms: None,
            consecutive_losses: 0,
            consecutive_wins: 0,
            in_feature: false,
            smoothed: PlayerStateVector::neutral(),
            adaptation: AudioAdaptation::neutral(),
        }
    }

    /// Process one behavioral sample and return updated Player State Vector.
    pub fn process(&mut self, sample: &BehavioralSample) -> &PlayerStateVector {
        let ts = sample.timestamp_ms;
        let hl = self.config.decay_half_life_s * 1000.0;

        // Update session start
        if self.session_start_ms.is_none() {
            self.session_start_ms = Some(ts);
        }

        match &sample.event {
            // ── Spin click ─────────────────────────────────────────────────
            BehavioralEvent::SpinClick { inter_spin_ms } => {
                // Normalize: 0 = impulsive (<200ms), 1 = hesitant (>4000ms)
                let norm = (*inter_spin_ms as f64 / 4000.0).clamp(0.0, 1.0);
                self.inter_spin_ms.push(ts, norm);
                self.total_spins += 1;
            }

            // ── Spin result ────────────────────────────────────────────────
            BehavioralEvent::SpinResult { outcome, win_credits, bet_credits } => {
                let score = outcome.win_score();
                self.win_scores.push(ts, score);

                if outcome.is_near_miss() {
                    self.near_miss_raw.push(ts, 1.0);
                } else {
                    self.near_miss_raw.push(ts, 0.0);
                }

                if outcome.is_win() || outcome.is_feature() {
                    self.consecutive_wins += 1;
                    self.consecutive_losses = 0;
                } else if !outcome.is_near_miss() {
                    self.consecutive_losses += 1;
                    self.consecutive_wins = 0;
                }

                if outcome.is_feature() {
                    self.in_feature = true;
                }

                // Win-to-bet ratio as a quality signal
                let wbr = if *bet_credits > 0.0 {
                    (*win_credits / bet_credits).clamp(0.0, 10.0) / 10.0
                } else { 0.0 };
                let _ = wbr; // used for future extension
            }

            // ── Bet change ─────────────────────────────────────────────────
            BehavioralEvent::BetChange { new_bet, prev_bet, after_loss } => {
                if *prev_bet > 0.0 {
                    // Normalized bet delta: +0.5 = bet doubled, -0.5 = bet halved
                    let delta = ((new_bet - prev_bet) / prev_bet).clamp(-1.0, 1.0);
                    // Positive chasing signal: increased bet after a loss
                    let chasing = if *after_loss && delta > 0.0 { delta } else { 0.0 };
                    self.bet_change.push(ts, chasing);
                }
            }

            // ── Pause ──────────────────────────────────────────────────────
            BehavioralEvent::Pause { duration_ms, after_loss } => {
                // Pause >5s after loss is a frustration/churn signal
                if *after_loss && *duration_ms > 5_000 {
                    let frustration_signal = (*duration_ms as f64 / 30_000.0).clamp(0.0, 1.0);
                    self.pause_signal.push(ts, frustration_signal);
                }
            }

            BehavioralEvent::FeatureEnd { .. } => {
                self.in_feature = false;
            }

            // Other events currently unused in state computation
            _ => {}
        }

        // ── Compute raw PSV ─────────────────────────────────────────────────
        let raw = self.compute_state_vector(ts, hl);

        // ── Smooth ─────────────────────────────────────────────────────────
        let smooth_coeff = self.config.smoothing;
        self.smoothed = smooth_state(&self.smoothed, &raw, smooth_coeff);

        // ── Compute adaptation ──────────────────────────────────────────────
        self.adaptation = AudioAdaptation::from_state(&self.smoothed, self.config.rg_mode_enabled);

        &self.smoothed
    }

    /// Batch-process a sequence of samples and return all state snapshots.
    pub fn simulate(&mut self, samples: &[BehavioralSample]) -> Vec<PlayerStateVector> {
        samples.iter().map(|sample| self.process(sample).clone()).collect()
    }

    /// Current Audio Adaptation (computed during last `process` call)
    pub fn adaptation(&self) -> &AudioAdaptation {
        &self.adaptation
    }

    /// Current Player State Vector (smoothed)
    pub fn state(&self) -> &PlayerStateVector {
        &self.smoothed
    }

    /// Reset engine state (new session)
    pub fn reset(&mut self) {
        self.inter_spin_ms.data.clear();
        self.win_scores.data.clear();
        self.near_miss_raw.data.clear();
        self.bet_change.data.clear();
        self.pause_signal.data.clear();
        self.total_spins = 0;
        self.session_start_ms = None;
        self.consecutive_losses = 0;
        self.consecutive_wins = 0;
        self.in_feature = false;
        self.smoothed = PlayerStateVector::neutral();
        self.adaptation = AudioAdaptation::neutral();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Core computation
    // ──────────────────────────────────────────────────────────────────────

    fn compute_state_vector(&self, now_ms: u64, hl_ms: f64) -> PlayerStateVector {
        let session_min = self.session_start_ms
            .map(|s| (now_ms.saturating_sub(s)) as f64 / 60_000.0)
            .unwrap_or(0.0);

        let win_rate  = self.win_scores.weighted_mean(now_ms, hl_ms);
        let nm_rate   = self.near_miss_raw.weighted_mean(now_ms, hl_ms);
        let spin_pace = self.inter_spin_ms.weighted_mean(now_ms, hl_ms);
        let chasing   = self.bet_change.weighted_mean(now_ms, hl_ms);
        let pause_f   = self.pause_signal.weighted_mean(now_ms, hl_ms);

        // Streak factors (capped to avoid runaway)
        let loss_streak_f = (self.consecutive_losses as f64 / 15.0).clamp(0.0, 1.0);
        let win_streak_f  = (self.consecutive_wins  as f64 / 5.0 ).clamp(0.0, 1.0);

        // ── 1. AROUSAL ─────────────────────────────────────────────────────
        // High when winning/near-miss or in feature; low when long pause/fatigued
        let arousal = (0.25
            + win_rate * 0.35
            + nm_rate  * 0.20
            + win_streak_f * 0.20
            - (session_min / 60.0) * 0.10
            + if self.in_feature { 0.20 } else { 0.0 })
            .clamp(0.0, 1.0);

        // ── 2. VALENCE ─────────────────────────────────────────────────────
        // Positive when winning, negative when losing streak + chasing
        let valence = (0.50
            + win_rate * 0.40
            - loss_streak_f * 0.35
            - chasing  * 0.20
            - pause_f  * 0.10
            + if self.in_feature { 0.15 } else { 0.0 })
            .clamp(0.0, 1.0);

        // ── 3. ENGAGEMENT ─────────────────────────────────────────────────
        // High in flow (consistent pace, wins), low when fatigued/frustrated
        let impulsive = 1.0 - spin_pace; // low inter-spin norm = impulsive = engaged
        let engagement = (0.60
            + impulsive * 0.20
            + win_streak_f * 0.15
            - loss_streak_f * 0.25
            - (session_min / 90.0) * 0.10
            - chasing * 0.10)
            .clamp(0.0, 1.0);

        // ── 4. RISK TOLERANCE ─────────────────────────────────────────────
        // Increases when chasing losses; decreases when cooling
        let risk_tolerance = (0.30
            + chasing * 0.50
            + loss_streak_f * 0.20
            - win_rate * 0.15)
            .clamp(0.0, 1.0);

        // ── 5. FRUSTRATION ────────────────────────────────────────────────
        // Loss streak + chasing + pauses after loss
        let frustration = (0.0
            + loss_streak_f * 0.50
            + chasing * 0.25
            + pause_f * 0.25)
            .clamp(0.0, 1.0);

        // ── 6. ANTICIPATION ───────────────────────────────────────────────
        // Near-miss + feature proximity + long losing stretch
        let anticipation = (0.20
            + nm_rate * 0.50
            + (if loss_streak_f > 0.4 { loss_streak_f * 0.20 } else { 0.0 }))
            .clamp(0.0, 1.0);

        // ── 7. FATIGUE ────────────────────────────────────────────────────
        // Builds over time + with high arousal exposure
        let session_fatigue = (session_min / 60.0).clamp(0.0, 1.0);
        let arousal_fatigue = if arousal > 0.70 {
            ((session_min * arousal) / 30.0).clamp(0.0, 1.0)
        } else { 0.0 };
        let fatigue = (session_fatigue * 0.60 + arousal_fatigue * 0.40).clamp(0.0, 1.0);

        // ── 8. CHURN PROBABILITY ──────────────────────────────────────────
        // High loss streak + frustration + low engagement → likely to quit
        let churn_probability = (0.10
            + frustration * 0.30
            + loss_streak_f * 0.25
            + fatigue * 0.20
            + (1.0 - engagement) * 0.15
            - win_rate * 0.20
            - if self.in_feature { 0.15 } else { 0.0 })
            .clamp(0.0, 1.0);

        PlayerStateVector {
            arousal,
            valence,
            engagement,
            risk_tolerance,
            frustration,
            anticipation,
            fatigue,
            churn_probability,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

fn smooth_state(old: &PlayerStateVector, raw: &PlayerStateVector, alpha: f64) -> PlayerStateVector {
    let s = |a: f64, b: f64| a * alpha + b * (1.0 - alpha);
    PlayerStateVector {
        arousal:           s(old.arousal,           raw.arousal),
        valence:           s(old.valence,           raw.valence),
        engagement:        s(old.engagement,        raw.engagement),
        risk_tolerance:    s(old.risk_tolerance,    raw.risk_tolerance),
        frustration:       s(old.frustration,       raw.frustration),
        anticipation:      s(old.anticipation,      raw.anticipation),
        fatigue:           s(old.fatigue,           raw.fatigue),
        churn_probability: s(old.churn_probability, raw.churn_probability),
    }
    .clamped()
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::SpinOutcome;

    fn default_engine() -> NeuroEngine {
        NeuroEngine::new(NeuroConfig {
            smoothing: 0.0, // no smoothing in tests (raw output)
            ..NeuroConfig::default()
        })
    }

    #[test]
    fn test_initial_state_is_neutral() {
        let engine = default_engine();
        let state = engine.state();
        assert!((0.20..=0.50).contains(&state.arousal));
        assert!((0.40..=0.60).contains(&state.valence));
    }

    #[test]
    fn test_win_streak_increases_arousal() {
        let mut engine = default_engine();
        let mut ts = 0u64;

        for _ in 0..5 {
            engine.process(&BehavioralSample::spin_click(ts, 1000));
            ts += 1000;
            engine.process(&BehavioralSample::spin_result(ts, SpinOutcome::BigWin, 50.0, 1.0));
            ts += 1000;
        }

        let state = engine.state();
        assert!(state.arousal > 0.5, "arousal={}", state.arousal);
        assert!(state.valence > 0.5, "valence={}", state.valence);
    }

    #[test]
    fn test_loss_streak_increases_frustration() {
        let mut engine = default_engine();
        let mut ts = 0u64;

        for _ in 0..12 {
            engine.process(&BehavioralSample::spin_click(ts, 1200));
            ts += 1200;
            engine.process(&BehavioralSample::spin_result(ts, SpinOutcome::Loss, 0.0, 1.0));
            ts += 500;
        }

        let state = engine.state();
        assert!(state.frustration > 0.3, "frustration={}", state.frustration);
        assert!(state.churn_probability > 0.2, "churn={}", state.churn_probability);
    }

    #[test]
    fn test_chasing_increases_risk_tolerance() {
        let mut engine = default_engine();
        let ts = 1000u64;

        engine.process(&BehavioralSample::spin_click(ts, 1000));
        engine.process(&BehavioralSample::spin_result(ts + 500, SpinOutcome::Loss, 0.0, 1.0));
        engine.process(&BehavioralSample::bet_change(ts + 600, 5.0, 1.0, true));

        let state = engine.state();
        assert!(state.risk_tolerance > 0.3, "risk={}", state.risk_tolerance);
    }

    #[test]
    fn test_near_miss_increases_anticipation() {
        let mut engine = default_engine();
        let mut ts = 0u64;

        for _ in 0..3 {
            engine.process(&BehavioralSample::spin_click(ts, 1000));
            ts += 1000;
            engine.process(&BehavioralSample::spin_result(ts, SpinOutcome::NearMiss, 0.0, 1.0));
            ts += 500;
        }

        let state = engine.state();
        assert!(state.anticipation > 0.25, "anticipation={}", state.anticipation);
    }

    #[test]
    fn test_simulate_returns_one_snapshot_per_sample() {
        let mut engine = default_engine();
        let samples: Vec<BehavioralSample> = (0..10).map(|i| {
            BehavioralSample::spin_click(i as u64 * 1000, 1000)
        }).collect();

        let results = engine.simulate(&samples);
        assert_eq!(results.len(), 10);
    }

    #[test]
    fn test_reset_clears_history() {
        let mut engine = default_engine();
        let mut ts = 0u64;

        // Build up some state
        for _ in 0..5 {
            engine.process(&BehavioralSample::spin_result(ts, SpinOutcome::Loss, 0.0, 1.0));
            ts += 1000;
        }
        engine.reset();

        let state = engine.state();
        // Should be back to neutral after reset
        assert!((0.20..=0.50).contains(&state.arousal));
        assert_eq!(engine.total_spins, 0);
    }

    #[test]
    fn test_all_state_fields_in_range_after_simulation() {
        let mut engine = default_engine();
        let mut ts = 0u64;
        let outcomes = [
            SpinOutcome::Loss, SpinOutcome::SmallWin, SpinOutcome::NearMiss,
            SpinOutcome::BigWin, SpinOutcome::FeatureTriggered, SpinOutcome::Loss,
        ];
        for (i, &outcome) in outcomes.iter().enumerate() {
            engine.process(&BehavioralSample::spin_click(ts, 1000));
            ts += 1000;
            engine.process(&BehavioralSample::spin_result(ts, outcome, if outcome.is_win() { 10.0 } else { 0.0 }, 1.0));
            ts += (i as u64 + 1) * 500;
        }

        let s = engine.state();
        for v in [s.arousal, s.valence, s.engagement, s.risk_tolerance,
                  s.frustration, s.anticipation, s.fatigue, s.churn_probability] {
            assert!((0.0..=1.0).contains(&v), "out of range: {v}");
        }
    }

    #[test]
    fn test_rg_intervention_on_chasing_player() {
        let mut engine = NeuroEngine::new(NeuroConfig {
            smoothing: 0.0,
            rg_mode_enabled: true,
            ..NeuroConfig::default()
        });
        let mut ts = 1000u64;

        // Simulate a chasing pattern: 15 losses + increasing bets + long pause
        for _ in 0..15 {
            engine.process(&BehavioralSample::spin_click(ts, 300)); // impulsive
            ts += 300;
            engine.process(&BehavioralSample::spin_result(ts, SpinOutcome::Loss, 0.0, 1.0));
            ts += 200;
        }
        engine.process(&BehavioralSample::bet_change(ts, 10.0, 1.0, true));
        ts += 100;
        engine.process(&BehavioralSample::pause(ts, 15_000, true));

        let adapt = engine.adaptation();
        // In RG mode, a high-risk player should get active intervention
        assert!(
            adapt.rg_intervention.is_some(),
            "Expected RG intervention for chasing player, got: {:?}", adapt.rg_intervention
        );
    }
}
