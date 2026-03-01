//! Burn Test — 10,000 deterministic spins measuring long-term drift.
//! Tracks: energy drift, harmonic creep, spectral bias, voice trend, fatigue accumulation.

use serde::{Deserialize, Serialize};
use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::qa::simulation::SimulationStep;

/// Trend direction for a metric over time.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrendDirection {
    Stable,
    Rising,
    Falling,
    Oscillating,
}

impl TrendDirection {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Stable => "Stable",
            Self::Rising => "Rising",
            Self::Falling => "Falling",
            Self::Oscillating => "Oscillating",
        }
    }
}

/// A single drift metric tracked over the burn test.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriftMetric {
    pub name: String,
    pub initial_value: f64,
    pub final_value: f64,
    pub peak_value: f64,
    pub min_value: f64,
    pub mean_value: f64,
    pub drift_total: f64,     // final - initial
    pub drift_pct: f64,       // drift as percentage of range
    pub trend: TrendDirection,
    /// Samples at 100-spin intervals for charting.
    pub samples: Vec<f64>,
}

impl DriftMetric {
    pub fn is_stable(&self, threshold: f64) -> bool {
        self.drift_pct.abs() < threshold
    }
}

/// Burn test configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BurnTestConfig {
    /// Total number of spins.
    pub total_spins: u32,
    /// Sample interval (every N spins, record a sample).
    pub sample_interval: u32,
    /// Base RTP for the simulation.
    pub base_rtp: f64,
    /// Win probability (0.0–1.0) — how often a spin wins.
    pub win_probability: f64,
    /// Average win multiplier when winning.
    pub avg_win_multiplier: f64,
    /// Max acceptable drift percentage before failure.
    pub max_drift_pct: f64,
    /// Max acceptable fatigue at end.
    pub max_final_fatigue: f64,
}

impl Default for BurnTestConfig {
    fn default() -> Self {
        Self {
            total_spins: 10_000,
            sample_interval: 100,
            base_rtp: 96.0,
            win_probability: 0.25,
            avg_win_multiplier: 5.0,
            max_drift_pct: 15.0,
            max_final_fatigue: 0.95,
        }
    }
}

/// Complete burn test metrics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BurnTestMetrics {
    pub energy_drift: DriftMetric,
    pub harmonic_creep: DriftMetric,
    pub spectral_bias: DriftMetric,
    pub voice_trend: DriftMetric,
    pub fatigue_accumulation: DriftMetric,
}

/// Burn test result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BurnTestResult {
    pub metrics: BurnTestMetrics,
    pub total_spins: u32,
    pub passed: bool,
    pub failures: Vec<String>,
    pub deterministic: bool,
    pub hash: String,
    pub duration_ms: u64,
}

impl BurnTestResult {
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }
}

/// Burn Test Engine.
#[derive(Debug)]
pub struct BurnTest {
    config: BurnTestConfig,
    last_result: Option<BurnTestResult>,
}

impl BurnTest {
    pub fn new(config: BurnTestConfig) -> Self {
        Self { config, last_result: None }
    }

    /// Run full 10,000-spin burn test.
    pub fn run(&mut self, aurexis_config: &AurexisConfig) -> &BurnTestResult {
        let start = std::time::Instant::now();

        let mut engine = AurexisEngine::with_config(aurexis_config.clone());
        engine.initialize();

        let sample_count = (self.config.total_spins / self.config.sample_interval) as usize;

        // Metric accumulators
        let mut energy_values = Vec::with_capacity(self.config.total_spins as usize);
        let mut harmonic_values = Vec::with_capacity(self.config.total_spins as usize);
        let mut spectral_values = Vec::with_capacity(self.config.total_spins as usize);
        let mut voice_values = Vec::with_capacity(self.config.total_spins as usize);
        let mut fatigue_values = Vec::with_capacity(self.config.total_spins as usize);

        let mut energy_samples = Vec::with_capacity(sample_count);
        let mut harmonic_samples = Vec::with_capacity(sample_count);
        let mut spectral_samples = Vec::with_capacity(sample_count);
        let mut voice_samples = Vec::with_capacity(sample_count);
        let mut fatigue_samples = Vec::with_capacity(sample_count);

        let mut hash = 0xcbf29ce484222325u64;

        // Deterministic pseudo-random for win pattern
        let mut rng_state = 0x12345678u64;

        for spin in 0..self.config.total_spins {
            // Deterministic win decision
            rng_state = rng_state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let win_roll = ((rng_state >> 33) as f64) / (u32::MAX as f64);
            let is_win = win_roll < self.config.win_probability as f64;
            let win_mult = if is_win { self.config.avg_win_multiplier * (0.5 + win_roll) } else { 0.0 };

            let step = SimulationStep {
                elapsed_ms: 50,
                volatility: 0.5,
                rtp: self.config.base_rtp,
                win_multiplier: win_mult,
                jackpot_proximity: if spin > self.config.total_spins.saturating_sub(100) { 0.5 } else { 0.0 },
                rms_db: if is_win { -16.0 } else { -24.0 },
                hf_db: if is_win { -20.0 } else { -30.0 },
            };

            engine.set_rtp(step.rtp);
            engine.set_volatility(step.volatility);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);
            let output = engine.compute(step.elapsed_ms);

            // Collect values
            energy_values.push(output.energy_overall_cap);
            harmonic_values.push(output.harmonic_excitation);
            spectral_values.push(output.sci_adv);
            voice_values.push((output.dpm_retained + output.dpm_attenuated) as f64);
            fatigue_values.push(output.fatigue_index);

            // Hash
            hash ^= output.energy_overall_cap.to_bits();
            hash = hash.wrapping_mul(0x100000001b3);

            // Sample at intervals
            if spin > 0 && spin % self.config.sample_interval == 0 {
                energy_samples.push(output.energy_overall_cap);
                harmonic_samples.push(output.harmonic_excitation);
                spectral_samples.push(output.sci_adv);
                voice_samples.push((output.dpm_retained + output.dpm_attenuated) as f64);
                fatigue_samples.push(output.fatigue_index);
            }
        }

        // Build drift metrics
        let energy_drift = build_drift_metric("Energy", &energy_values, &energy_samples);
        let harmonic_creep = build_drift_metric("Harmonic", &harmonic_values, &harmonic_samples);
        let spectral_bias = build_drift_metric("Spectral (SCI)", &spectral_values, &spectral_samples);
        let voice_trend = build_drift_metric("Voice Count", &voice_values, &voice_samples);
        let fatigue_accumulation = build_drift_metric("Fatigue", &fatigue_values, &fatigue_samples);

        // Verify determinism — run again with same sequence
        let replay_hash = {
            let mut engine2 = AurexisEngine::with_config(aurexis_config.clone());
            engine2.initialize();
            let mut h = 0xcbf29ce484222325u64;
            let mut rng2 = 0x12345678u64;

            for spin in 0..self.config.total_spins {
                rng2 = rng2.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                let win_roll = ((rng2 >> 33) as f64) / (u32::MAX as f64);
                let is_win = win_roll < self.config.win_probability as f64;
                let win_mult = if is_win { self.config.avg_win_multiplier * (0.5 + win_roll) } else { 0.0 };

                engine2.set_rtp(self.config.base_rtp);
                engine2.set_volatility(0.5);
                engine2.set_win(win_mult, 1.0, if spin > self.config.total_spins.saturating_sub(100) { 0.5 } else { 0.0 });
                engine2.set_metering(if is_win { -16.0 } else { -24.0 }, if is_win { -20.0 } else { -30.0 });
                let output = engine2.compute(50);
                h ^= output.energy_overall_cap.to_bits();
                h = h.wrapping_mul(0x100000001b3);
            }
            format!("{:016x}", h)
        };

        let hash_str = format!("{:016x}", hash);
        let deterministic = hash_str == replay_hash;

        // Validate
        let mut failures = Vec::new();
        if energy_drift.drift_pct.abs() > self.config.max_drift_pct {
            failures.push(format!("Energy drift {:.1}% exceeds max {:.1}%",
                energy_drift.drift_pct, self.config.max_drift_pct));
        }
        if harmonic_creep.drift_pct.abs() > self.config.max_drift_pct {
            failures.push(format!("Harmonic creep {:.1}% exceeds max {:.1}%",
                harmonic_creep.drift_pct, self.config.max_drift_pct));
        }
        if fatigue_accumulation.final_value > self.config.max_final_fatigue {
            failures.push(format!("Final fatigue {:.3} exceeds max {:.3}",
                fatigue_accumulation.final_value, self.config.max_final_fatigue));
        }
        if !deterministic {
            failures.push("Non-deterministic: hash mismatch on replay".into());
        }

        let metrics = BurnTestMetrics {
            energy_drift,
            harmonic_creep,
            spectral_bias,
            voice_trend,
            fatigue_accumulation,
        };

        self.last_result = Some(BurnTestResult {
            metrics,
            total_spins: self.config.total_spins,
            passed: failures.is_empty(),
            failures,
            deterministic,
            hash: hash_str,
            duration_ms: start.elapsed().as_millis() as u64,
        });

        self.last_result.as_ref().unwrap()
    }

    pub fn last_result(&self) -> Option<&BurnTestResult> {
        self.last_result.as_ref()
    }

    pub fn config(&self) -> &BurnTestConfig {
        &self.config
    }
}

/// Build a drift metric from a value series.
fn build_drift_metric(name: &str, values: &[f64], samples: &[f64]) -> DriftMetric {
    if values.is_empty() {
        return DriftMetric {
            name: name.into(),
            initial_value: 0.0, final_value: 0.0,
            peak_value: 0.0, min_value: 0.0, mean_value: 0.0,
            drift_total: 0.0, drift_pct: 0.0,
            trend: TrendDirection::Stable,
            samples: vec![],
        };
    }

    let initial = values[0];
    let final_val = *values.last().unwrap();
    let peak = values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let min = values.iter().cloned().fold(f64::INFINITY, f64::min);
    let sum: f64 = values.iter().sum();
    let mean = sum / values.len() as f64;
    let drift = final_val - initial;
    let range = peak - min;
    let drift_pct = if range > f64::EPSILON { (drift / range) * 100.0 } else { 0.0 };

    // Determine trend from samples
    let trend = if samples.len() < 3 {
        TrendDirection::Stable
    } else {
        let first_third: f64 = samples[..samples.len()/3].iter().sum::<f64>() / (samples.len()/3) as f64;
        let last_third: f64 = samples[samples.len()*2/3..].iter().sum::<f64>() / (samples.len() - samples.len()*2/3) as f64;
        let diff = last_third - first_third;
        let mid_third: f64 = samples[samples.len()/3..samples.len()*2/3].iter().sum::<f64>()
            / (samples.len()*2/3 - samples.len()/3) as f64;

        if range < f64::EPSILON || diff.abs() < range * 0.05 {
            TrendDirection::Stable
        } else if (mid_third > first_third && mid_third > last_third) || (mid_third < first_third && mid_third < last_third) {
            TrendDirection::Oscillating
        } else if diff > 0.0 {
            TrendDirection::Rising
        } else {
            TrendDirection::Falling
        }
    };

    DriftMetric {
        name: name.into(),
        initial_value: initial,
        final_value: final_val,
        peak_value: peak,
        min_value: min,
        mean_value: mean,
        drift_total: drift,
        drift_pct,
        trend,
        samples: samples.to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_burn_test_config_defaults() {
        let config = BurnTestConfig::default();
        assert_eq!(config.total_spins, 10_000);
        assert_eq!(config.sample_interval, 100);
    }

    #[test]
    fn test_burn_test_small() {
        // Small burn test for CI speed
        let config = BurnTestConfig {
            total_spins: 100,
            sample_interval: 10,
            ..Default::default()
        };
        let aurexis_config = AurexisConfig::default();
        let mut burn = BurnTest::new(config);
        let result = burn.run(&aurexis_config);

        assert_eq!(result.total_spins, 100);
        assert!(result.deterministic);
        assert_eq!(result.metrics.energy_drift.samples.len(), 9); // 100/10 - 1
    }

    #[test]
    fn test_drift_metric_stable() {
        let values: Vec<f64> = (0..100).map(|_| 0.5).collect();
        let samples: Vec<f64> = (0..10).map(|_| 0.5).collect();
        let metric = build_drift_metric("Test", &values, &samples);
        assert_eq!(metric.trend, TrendDirection::Stable);
        assert!(metric.drift_pct.abs() < 0.01);
    }

    #[test]
    fn test_drift_metric_rising() {
        let values: Vec<f64> = (0..100).map(|i| i as f64 / 100.0).collect();
        let samples: Vec<f64> = (0..10).map(|i| i as f64 / 10.0).collect();
        let metric = build_drift_metric("Test", &values, &samples);
        assert_eq!(metric.trend, TrendDirection::Rising);
    }

    #[test]
    fn test_trend_direction_labels() {
        assert_eq!(TrendDirection::Stable.label(), "Stable");
        assert_eq!(TrendDirection::Rising.label(), "Rising");
        assert_eq!(TrendDirection::Falling.label(), "Falling");
        assert_eq!(TrendDirection::Oscillating.label(), "Oscillating");
    }

    #[test]
    fn test_burn_test_determinism() {
        let config = BurnTestConfig {
            total_spins: 50,
            sample_interval: 10,
            ..Default::default()
        };
        let aurexis_config = AurexisConfig::default();
        let mut burn = BurnTest::new(config);
        let result = burn.run(&aurexis_config);
        assert!(result.deterministic);
    }
}
