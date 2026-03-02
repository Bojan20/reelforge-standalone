//! Auto Regression — on config change, run 10 .fftrace sessions + stress scenarios.
//! Validates hash match across all replay sessions.

use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::qa::pbse::SimulationDomain;
use crate::qa::simulation::SimulationStep;
use serde::{Deserialize, Serialize};

/// Stress scenario for regression testing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StressScenario {
    NormalMix,
    LossStreak,
    WinEscalation,
    FeatureOverlap,
    JackpotRun,
    TurboBurst,
    AutoplayMarathon,
    SessionDrift,
    HookCollision,
    MaxVoiceLoad,
}

impl StressScenario {
    pub fn label(&self) -> &'static str {
        match self {
            Self::NormalMix => "Normal Mix",
            Self::LossStreak => "Loss Streak",
            Self::WinEscalation => "Win Escalation",
            Self::FeatureOverlap => "Feature Overlap",
            Self::JackpotRun => "Jackpot Run",
            Self::TurboBurst => "Turbo Burst",
            Self::AutoplayMarathon => "Autoplay Marathon",
            Self::SessionDrift => "Session Drift",
            Self::HookCollision => "Hook Collision",
            Self::MaxVoiceLoad => "Max Voice Load",
        }
    }

    pub fn all() -> &'static [StressScenario] {
        &[
            Self::NormalMix,
            Self::LossStreak,
            Self::WinEscalation,
            Self::FeatureOverlap,
            Self::JackpotRun,
            Self::TurboBurst,
            Self::AutoplayMarathon,
            Self::SessionDrift,
            Self::HookCollision,
            Self::MaxVoiceLoad,
        ]
    }

    /// Map to PBSE simulation domain.
    pub fn to_pbse_domain(&self) -> SimulationDomain {
        match self {
            Self::NormalMix => SimulationDomain::SpinSequences,
            Self::LossStreak => SimulationDomain::LossStreaks,
            Self::WinEscalation => SimulationDomain::WinStreaks,
            Self::FeatureOverlap => SimulationDomain::FeatureOverlaps,
            Self::JackpotRun => SimulationDomain::JackpotEscalation,
            Self::TurboBurst => SimulationDomain::TurboCompression,
            Self::AutoplayMarathon => SimulationDomain::AutoplayBurst,
            Self::SessionDrift => SimulationDomain::LongSessionDrift,
            Self::HookCollision => SimulationDomain::HookBurstCollision,
            Self::MaxVoiceLoad => SimulationDomain::CascadeChains,
        }
    }
}

/// Regression run configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegressionConfig {
    pub session_count: usize,
    pub spins_per_session: u32,
    pub scenarios: Vec<StressScenario>,
    pub verify_determinism: bool,
    pub max_deviation_pct: f64,
}

impl Default for RegressionConfig {
    fn default() -> Self {
        Self {
            session_count: 10,
            spins_per_session: 100,
            scenarios: StressScenario::all().to_vec(),
            verify_determinism: true,
            max_deviation_pct: 0.0,
        }
    }
}

/// Status of a single regression run.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum RegressionStatus {
    Pending,
    Running,
    Passed,
    Failed(String),
}

/// A single regression run result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegressionRun {
    pub session_index: usize,
    pub scenario: StressScenario,
    pub status: RegressionStatus,
    pub spin_count: u32,
    pub hash_record: String,
    pub hash_replay: String,
    pub deterministic: bool,
    pub peak_energy: f64,
    pub peak_voices: u32,
    pub peak_fatigue: f64,
    pub duration_ms: u64,
}

/// Complete regression result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegressionResult {
    pub runs: Vec<RegressionRun>,
    pub all_passed: bool,
    pub deterministic: bool,
    pub total_spins: u64,
    pub failed_count: usize,
    pub duration_ms: u64,
}

impl RegressionResult {
    pub fn pass_rate(&self) -> f64 {
        if self.runs.is_empty() {
            return 0.0;
        }
        let passed = self
            .runs
            .iter()
            .filter(|r| r.status == RegressionStatus::Passed)
            .count();
        passed as f64 / self.runs.len() as f64
    }

    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }
}

/// Auto Regression Engine.
#[derive(Debug)]
pub struct AutoRegression {
    config: RegressionConfig,
    last_result: Option<RegressionResult>,
}

impl AutoRegression {
    pub fn new(config: RegressionConfig) -> Self {
        Self {
            config,
            last_result: None,
        }
    }

    /// Run full regression suite using AurexisEngine compute() API.
    pub fn run(&mut self, aurexis_config: &AurexisConfig) -> &RegressionResult {
        let start = std::time::Instant::now();
        let mut runs = Vec::new();
        let mut all_deterministic = true;

        for (session_idx, scenario) in self.config.scenarios.iter().enumerate() {
            let run_start = std::time::Instant::now();
            let domain = scenario.to_pbse_domain();
            let steps = generate_stress_steps(domain, self.config.spins_per_session);

            // Record pass
            let record_hash = execute_and_hash(aurexis_config, &steps);

            // Replay pass — identical run, verify determinism
            let (replay_hash, peak_energy, peak_voices, peak_fatigue) =
                execute_and_collect_metrics(aurexis_config, &steps);

            let deterministic = record_hash == replay_hash;
            if !deterministic {
                all_deterministic = false;
            }

            let status = if deterministic {
                RegressionStatus::Passed
            } else {
                RegressionStatus::Failed(format!(
                    "Hash mismatch: record={}, replay={}",
                    record_hash, replay_hash
                ))
            };

            runs.push(RegressionRun {
                session_index: session_idx,
                scenario: *scenario,
                status,
                spin_count: self.config.spins_per_session,
                hash_record: record_hash,
                hash_replay: replay_hash,
                deterministic,
                peak_energy,
                peak_voices,
                peak_fatigue,
                duration_ms: run_start.elapsed().as_millis() as u64,
            });
        }

        let failed_count = runs
            .iter()
            .filter(|r| !matches!(r.status, RegressionStatus::Passed))
            .count();
        let total_spins = runs.iter().map(|r| r.spin_count as u64).sum();

        self.last_result = Some(RegressionResult {
            runs,
            all_passed: failed_count == 0,
            deterministic: all_deterministic,
            total_spins,
            failed_count,
            duration_ms: start.elapsed().as_millis() as u64,
        });

        self.last_result.as_ref().unwrap()
    }

    pub fn last_result(&self) -> Option<&RegressionResult> {
        self.last_result.as_ref()
    }

    pub fn config(&self) -> &RegressionConfig {
        &self.config
    }
}

/// Execute steps and return FNV-1a hash of all outputs.
fn execute_and_hash(config: &AurexisConfig, steps: &[SimulationStep]) -> String {
    let mut engine = AurexisEngine::with_config(config.clone());
    engine.initialize();
    let mut hash = 0xcbf29ce484222325u64;
    for step in steps {
        engine.set_rtp(step.rtp);
        engine.set_volatility(step.volatility);
        engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
        engine.set_metering(step.rms_db, step.hf_db);
        let output = engine.compute(step.elapsed_ms);
        hash ^= output.energy_overall_cap.to_bits();
        hash = hash.wrapping_mul(0x100000001b3);
        hash ^= output.fatigue_index.to_bits();
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", hash)
}

/// Execute steps, collect hash AND peak metrics.
fn execute_and_collect_metrics(
    config: &AurexisConfig,
    steps: &[SimulationStep],
) -> (String, f64, u32, f64) {
    let mut engine = AurexisEngine::with_config(config.clone());
    engine.initialize();
    let mut hash = 0xcbf29ce484222325u64;
    let mut peak_energy = 0.0f64;
    let mut peak_voices = 0u32;
    let mut peak_fatigue = 0.0f64;

    for step in steps {
        engine.set_rtp(step.rtp);
        engine.set_volatility(step.volatility);
        engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
        engine.set_metering(step.rms_db, step.hf_db);
        let output = engine.compute(step.elapsed_ms);

        hash ^= output.energy_overall_cap.to_bits();
        hash = hash.wrapping_mul(0x100000001b3);
        hash ^= output.fatigue_index.to_bits();
        hash = hash.wrapping_mul(0x100000001b3);

        peak_energy = peak_energy.max(output.energy_overall_cap);
        peak_voices = peak_voices.max(output.dpm_retained + output.dpm_attenuated);
        peak_fatigue = peak_fatigue.max(output.fatigue_index);
    }
    (
        format!("{:016x}", hash),
        peak_energy,
        peak_voices,
        peak_fatigue,
    )
}

/// Generate simulation steps for a stress scenario.
fn generate_stress_steps(domain: SimulationDomain, count: u32) -> Vec<SimulationStep> {
    let mut steps = Vec::with_capacity(count as usize);
    for i in 0..count {
        let step = match domain {
            SimulationDomain::LossStreaks => SimulationStep {
                win_multiplier: 0.0,
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::WinStreaks => SimulationStep {
                win_multiplier: (i as f64 + 1.0) * 2.0,
                rtp: 96.0,
                rms_db: -16.0,
                ..Default::default()
            },
            SimulationDomain::CascadeChains => SimulationStep {
                win_multiplier: if i % 3 == 0 { 5.0 } else { 0.0 },
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::FeatureOverlaps => SimulationStep {
                win_multiplier: 3.0,
                rtp: 96.0,
                jackpot_proximity: if i % 4 == 0 { 0.5 } else { 0.0 },
                ..Default::default()
            },
            SimulationDomain::JackpotEscalation => SimulationStep {
                win_multiplier: if i > count.saturating_sub(5) {
                    1000.0
                } else {
                    0.0
                },
                jackpot_proximity: i as f64 / count as f64,
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::TurboCompression => SimulationStep {
                elapsed_ms: 25, // Turbo = faster ticks
                win_multiplier: if i % 3 == 0 { 2.0 } else { 0.0 },
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::AutoplayBurst => SimulationStep {
                win_multiplier: if i % 7 == 0 { 3.0 } else { 0.0 },
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::LongSessionDrift => SimulationStep {
                win_multiplier: if i % 10 == 0 { 2.0 } else { 0.0 },
                rtp: 96.0,
                ..Default::default()
            },
            SimulationDomain::HookBurstCollision => SimulationStep {
                win_multiplier: 1.0,
                rtp: 96.0,
                jackpot_proximity: if i % 2 == 0 { 0.3 } else { 0.0 },
                ..Default::default()
            },
            _ => SimulationStep {
                win_multiplier: if i % 5 == 0 { 2.0 } else { 0.0 },
                rtp: 96.0,
                ..Default::default()
            },
        };
        steps.push(step);
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stress_scenarios() {
        assert_eq!(StressScenario::all().len(), 10);
    }

    #[test]
    fn test_regression_config_defaults() {
        let config = RegressionConfig::default();
        assert_eq!(config.session_count, 10);
        assert_eq!(config.scenarios.len(), 10);
        assert!(config.verify_determinism);
    }

    #[test]
    fn test_regression_run() {
        let config = RegressionConfig {
            session_count: 2,
            spins_per_session: 10,
            scenarios: vec![StressScenario::NormalMix, StressScenario::LossStreak],
            verify_determinism: true,
            max_deviation_pct: 0.0,
        };
        let aurexis_config = AurexisConfig::default();
        let mut regression = AutoRegression::new(config);
        let result = regression.run(&aurexis_config);

        assert_eq!(result.runs.len(), 2);
        assert!(result.deterministic);
        assert!(result.all_passed);
        assert!((result.pass_rate() - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_generate_stress_steps() {
        let steps = generate_stress_steps(SimulationDomain::LossStreaks, 50);
        assert_eq!(steps.len(), 50);
        assert!(steps.iter().all(|s| s.win_multiplier == 0.0));
    }

    #[test]
    fn test_regression_result_json() {
        let result = RegressionResult {
            runs: vec![],
            all_passed: true,
            deterministic: true,
            total_spins: 0,
            failed_count: 0,
            duration_ms: 0,
        };
        assert!(result.to_json().is_ok());
    }
}
