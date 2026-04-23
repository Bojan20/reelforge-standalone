//! Session simulation and player archetypes for NeuroAudio Authoring Mode (T4.8).
//!
//! Allows audio designers to preview how the audio mix will adapt for
//! different player behavioral profiles without running a live game.

use serde::{Deserialize, Serialize};
use crate::engine::{NeuroConfig, NeuroEngine};
use crate::events::{BehavioralEvent, BehavioralSample, SpinOutcome};
use crate::state::{AudioAdaptation, PlayerStateVector};

// ─────────────────────────────────────────────────────────────────────────────
// PLAYER ARCHETYPES
// ─────────────────────────────────────────────────────────────────────────────

/// Predefined player behavioral profiles for authoring preview
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArchetypePreset {
    /// Regular recreational player, relaxed pace, stays within budget
    Casual,
    /// Engaged player, consistent pace, adapts bets rationally
    Regular,
    /// High-stakes player, large bets, very sensitive to big wins
    HighRoller,
    /// Player on a long losing streak, frustrated, may be chasing
    Frustrated,
    /// Early-session player with minimal history
    NewPlayer,
    /// Player near session end, fatigued, slowing down
    Fatigued,
    /// Feature-bonus focused player, gets excited during features
    FeatureFocused,
    /// Autoplay user, disengaged, minimal interaction signals
    Autoplay,
}

impl ArchetypePreset {
    pub fn display_name(self) -> &'static str {
        match self {
            ArchetypePreset::Casual         => "Casual",
            ArchetypePreset::Regular        => "Regular",
            ArchetypePreset::HighRoller     => "High Roller",
            ArchetypePreset::Frustrated     => "Frustrated",
            ArchetypePreset::NewPlayer      => "New Player",
            ArchetypePreset::Fatigued       => "Fatigued",
            ArchetypePreset::FeatureFocused => "Feature Focused",
            ArchetypePreset::Autoplay       => "Autoplay",
        }
    }

    /// Generate a representative sequence of behavioral samples for this archetype.
    /// `spin_count` — how many spins to simulate (recommend 50–200).
    pub fn generate_samples(self, spin_count: usize) -> Vec<BehavioralSample> {
        let mut ts = 0u64;
        let mut samples = Vec::with_capacity(spin_count * 2);

        match self {
            ArchetypePreset::Casual => {
                // Relaxed pace: 2–4s between spins, mild wins/losses
                for i in 0..spin_count {
                    let inter_ms = 2500 + (i % 5) * 400;
                    samples.push(BehavioralSample::spin_click(ts, inter_ms as u64));
                    ts += inter_ms as u64;

                    let outcome = if i % 4 == 0 { SpinOutcome::SmallWin }
                                  else if i % 9 == 0 { SpinOutcome::MediumWin }
                                  else { SpinOutcome::Loss };
                    let win = if outcome.is_win() { 3.0 } else { 0.0 };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 500;
                }
            }

            ArchetypePreset::Regular => {
                // Steady pace: 1.5–2.5s, mixed outcomes, occasional bet adjust
                for i in 0..spin_count {
                    let inter_ms = 1500 + (i % 3) * 300;
                    samples.push(BehavioralSample::spin_click(ts, inter_ms as u64));
                    ts += inter_ms as u64;

                    let outcome = match i % 7 {
                        0 => SpinOutcome::SmallWin,
                        3 => SpinOutcome::MediumWin,
                        6 => SpinOutcome::NearMiss,
                        _ => SpinOutcome::Loss,
                    };
                    let win = match outcome {
                        SpinOutcome::SmallWin => 2.5,
                        SpinOutcome::MediumWin => 12.0,
                        _ => 0.0,
                    };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 400;

                    // Bet adjustment every 20 spins
                    if i == 20 {
                        samples.push(BehavioralSample::bet_change(ts, 2.0, 1.0, false));
                        ts += 200;
                    }
                }
            }

            ArchetypePreset::HighRoller => {
                // Fast pace, big bets, big wins, celebratory pauses
                for i in 0..spin_count {
                    let inter_ms = 800 + (i % 3) * 200;
                    samples.push(BehavioralSample::spin_click(ts, inter_ms as u64));
                    ts += inter_ms as u64;

                    let outcome = match i % 5 {
                        0 => SpinOutcome::SmallWin,
                        2 => SpinOutcome::BigWin,
                        4 => if i % 20 == 4 { SpinOutcome::MegaWin } else { SpinOutcome::MediumWin },
                        _ => SpinOutcome::Loss,
                    };
                    let win = match outcome {
                        SpinOutcome::SmallWin  => 25.0,
                        SpinOutcome::MediumWin => 100.0,
                        SpinOutcome::BigWin    => 500.0,
                        SpinOutcome::MegaWin   => 2000.0,
                        _ => 0.0,
                    };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 50.0));
                    ts += 300;
                }
            }

            ArchetypePreset::Frustrated => {
                // Long losing streak, impulsive clicks, chasing, frustration pauses
                for i in 0..spin_count {
                    // Increasingly impulsive as losses mount
                    let inter_ms = (1500u64).saturating_sub((i * 30).min(1200) as u64);
                    samples.push(BehavioralSample::spin_click(ts, inter_ms));
                    ts += inter_ms;

                    // 85% loss rate
                    let is_win = i % 7 == 0;
                    let outcome = if is_win { SpinOutcome::SmallWin }
                                  else if i % 11 == 0 { SpinOutcome::NearMiss }
                                  else { SpinOutcome::Loss };
                    let win = if is_win { 2.0 } else { 0.0 };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 400;

                    // Bet chasing every 5 losses
                    if i > 5 && i % 5 == 0 && !is_win {
                        let new_bet = 1.0 + (i / 5) as f64;
                        samples.push(BehavioralSample::bet_change(ts, new_bet, new_bet - 1.0, true));
                        ts += 200;
                    }

                    // Frustration pause every 10 losses
                    if i > 0 && i % 10 == 0 && !is_win {
                        samples.push(BehavioralSample::pause(ts, 8_000, true));
                        ts += 8_000;
                    }
                }
            }

            ArchetypePreset::NewPlayer => {
                // Cautious pace, learning, some pauses to read paytable
                for i in 0..spin_count {
                    let inter_ms = 3500 + (i % 4) * 500;
                    samples.push(BehavioralSample::spin_click(ts, inter_ms as u64));
                    ts += inter_ms as u64;

                    let outcome = if i % 5 == 0 { SpinOutcome::SmallWin } else { SpinOutcome::Loss };
                    let win = if outcome.is_win() { 2.0 } else { 0.0 };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 600;

                    // Menu opens to check paytable
                    if i == 5 || i == 15 {
                        samples.push(BehavioralSample::new(ts, BehavioralEvent::MenuOpen));
                        ts += 5_000;
                    }
                }
            }

            ArchetypePreset::Fatigued => {
                // Slowing down significantly, occasional near-miss keeps interest
                for i in 0..spin_count {
                    let inter_ms = 2000 + (i * 40).min(6000) as u64;
                    samples.push(BehavioralSample::spin_click(ts, inter_ms));
                    ts += inter_ms;

                    let outcome = match i % 8 {
                        0 => SpinOutcome::SmallWin,
                        4 => SpinOutcome::NearMiss,
                        _ => SpinOutcome::Loss,
                    };
                    let win = if matches!(outcome, SpinOutcome::SmallWin) { 2.0 } else { 0.0 };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 600;
                }
            }

            ArchetypePreset::FeatureFocused => {
                // Moderate play until feature, then intense engagement during feature
                let feature_start = spin_count / 3;
                let feature_end = feature_start + spin_count / 4;

                for i in 0..spin_count {
                    let inter_ms = if i >= feature_start && i < feature_end { 600 } else { 2000 };
                    samples.push(BehavioralSample::spin_click(ts, inter_ms));
                    ts += inter_ms;

                    let outcome = if i == feature_start {
                        SpinOutcome::FeatureTriggered
                    } else if i >= feature_start && i < feature_end {
                        if i % 3 == 0 { SpinOutcome::BigWin } else { SpinOutcome::SmallWin }
                    } else if i % 5 == 0 {
                        SpinOutcome::SmallWin
                    } else {
                        SpinOutcome::Loss
                    };
                    let win = match outcome {
                        SpinOutcome::SmallWin => 3.0,
                        SpinOutcome::BigWin => 50.0,
                        SpinOutcome::FeatureTriggered => 0.0,
                        _ => 0.0,
                    };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 400;

                    // Feature end
                    if i == feature_end {
                        samples.push(BehavioralSample::new(ts, BehavioralEvent::FeatureEnd {
                            feature_name: "free_spins".to_string(),
                            total_win_credits: 250.0,
                        }));
                        ts += 1000;
                    }
                }
            }

            ArchetypePreset::Autoplay => {
                // Uniform 2s intervals, no manual interactions
                for i in 0..spin_count {
                    samples.push(BehavioralSample::spin_click(ts, 2000));
                    ts += 2000;

                    let outcome = if i % 6 == 0 { SpinOutcome::SmallWin }
                                  else if i % 12 == 0 { SpinOutcome::MediumWin }
                                  else { SpinOutcome::Loss };
                    let win = match outcome {
                        SpinOutcome::SmallWin => 2.5,
                        SpinOutcome::MediumWin => 15.0,
                        _ => 0.0,
                    };
                    samples.push(BehavioralSample::spin_result(ts, outcome, win, 1.0));
                    ts += 300;
                }
                // Toggle autoplay at start
                samples.insert(0, BehavioralSample::new(0, BehavioralEvent::AutoplayToggle { enabled: true }));
            }
        }

        samples
    }

    pub fn all() -> Vec<ArchetypePreset> {
        vec![
            ArchetypePreset::Casual,
            ArchetypePreset::Regular,
            ArchetypePreset::HighRoller,
            ArchetypePreset::Frustrated,
            ArchetypePreset::NewPlayer,
            ArchetypePreset::Fatigued,
            ArchetypePreset::FeatureFocused,
            ArchetypePreset::Autoplay,
        ]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMULATION
// ─────────────────────────────────────────────────────────────────────────────

/// Request for a session simulation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSimulation {
    pub archetype: ArchetypePreset,
    /// Number of spins to simulate (1–500)
    pub spin_count: usize,
    pub config: NeuroConfig,
}

/// Complete simulation result with per-sample snapshots
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    pub archetype: ArchetypePreset,
    pub spin_count: usize,
    /// Player State Vector snapshot after each behavioral sample
    pub state_timeline: Vec<PlayerStateVector>,
    /// Audio Adaptation snapshot after each behavioral sample
    pub adaptation_timeline: Vec<AudioAdaptation>,
    /// Final Player State Vector
    pub final_state: PlayerStateVector,
    /// Final Audio Adaptation
    pub final_adaptation: AudioAdaptation,
    /// Peak churn probability observed during session
    pub peak_churn: f64,
    /// Fraction of session with active RG intervention
    pub rg_intervention_fraction: f64,
}

impl SimulationResult {
    pub fn run(sim: &SessionSimulation) -> Self {
        let mut engine = NeuroEngine::new(sim.config.clone());
        let count = sim.spin_count.clamp(1, 500);
        let samples = sim.archetype.generate_samples(count);

        let mut states  = Vec::with_capacity(samples.len());
        let mut adapts  = Vec::with_capacity(samples.len());
        let mut peak_churn = 0.0f64;
        let mut rg_active_count = 0usize;

        for sample in &samples {
            let state = engine.process(sample).clone();
            let adapt = engine.adaptation().clone();

            peak_churn = peak_churn.max(state.churn_probability);
            if adapt.rg_intervention.is_some() {
                rg_active_count += 1;
            }

            states.push(state);
            adapts.push(adapt);
        }

        let final_state = states.last().cloned().unwrap_or(PlayerStateVector::neutral());
        let final_adapt = adapts.last().cloned().unwrap_or(AudioAdaptation::neutral());
        let rg_frac = if !samples.is_empty() {
            rg_active_count as f64 / samples.len() as f64
        } else { 0.0 };

        Self {
            archetype: sim.archetype,
            spin_count: count,
            state_timeline: states,
            adaptation_timeline: adapts,
            final_state,
            final_adaptation: final_adapt,
            peak_churn,
            rg_intervention_fraction: rg_frac,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_archetypes_generate_samples() {
        for archetype in ArchetypePreset::all() {
            let samples = archetype.generate_samples(50);
            assert!(!samples.is_empty(), "{:?} generated no samples", archetype);
        }
    }

    #[test]
    fn test_frustrated_archetype_produces_high_churn() {
        let sim = SessionSimulation {
            archetype: ArchetypePreset::Frustrated,
            spin_count: 100,
            config: NeuroConfig { smoothing: 0.0, ..NeuroConfig::default() },
        };
        let result = SimulationResult::run(&sim);
        assert!(result.peak_churn > 0.3, "peak_churn={}", result.peak_churn);
    }

    #[test]
    fn test_casual_archetype_produces_low_risk() {
        let sim = SessionSimulation {
            archetype: ArchetypePreset::Casual,
            spin_count: 80,
            config: NeuroConfig { smoothing: 0.0, ..NeuroConfig::default() },
        };
        let result = SimulationResult::run(&sim);
        let risk = result.final_state.rg_risk_score();
        assert!(risk < 0.60, "risk={}", risk);
    }

    #[test]
    fn test_simulation_timeline_length_matches_samples() {
        let archetype = ArchetypePreset::Regular;
        let spin_count = 50;
        let samples = archetype.generate_samples(spin_count);
        let sim = SessionSimulation {
            archetype,
            spin_count,
            config: NeuroConfig::default(),
        };
        let result = SimulationResult::run(&sim);
        assert_eq!(result.state_timeline.len(), samples.len());
        assert_eq!(result.adaptation_timeline.len(), samples.len());
    }

    #[test]
    fn test_feature_focused_archetype_triggers_rg_rarely() {
        let sim = SessionSimulation {
            archetype: ArchetypePreset::FeatureFocused,
            spin_count: 80,
            config: NeuroConfig { rg_mode_enabled: true, smoothing: 0.0, ..NeuroConfig::default() },
        };
        let result = SimulationResult::run(&sim);
        // Feature-focused shouldn't be high-risk
        assert!(result.rg_intervention_fraction < 0.50,
            "rg_frac={}", result.rg_intervention_fraction);
    }

    #[test]
    fn test_all_state_fields_bounded_across_all_archetypes() {
        for archetype in ArchetypePreset::all() {
            let sim = SessionSimulation {
                archetype,
                spin_count: 60,
                config: NeuroConfig { smoothing: 0.0, ..NeuroConfig::default() },
            };
            let result = SimulationResult::run(&sim);
            for state in &result.state_timeline {
                for v in [state.arousal, state.valence, state.engagement, state.risk_tolerance,
                          state.frustration, state.anticipation, state.fatigue, state.churn_probability] {
                    assert!((0.0..=1.0).contains(&v),
                        "{:?}: field out of range: {v}", archetype);
                }
            }
        }
    }
}
