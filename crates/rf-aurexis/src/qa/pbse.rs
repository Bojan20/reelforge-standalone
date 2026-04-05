//! PBSE: Pre-Bake Simulation Engine
//!
//! Deterministic stress-test before BAKE. Runs 10 simulation domains,
//! validates metrics, checks determinism, and gates BAKE on pass/fail.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §8

use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::core::parameter_map::DeterministicParameterMap;
use crate::qa::determinism::ReplayVerifier;
use crate::qa::simulation::SimulationStep;

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// 10 simulation domains.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum SimulationDomain {
    SpinSequences = 0,
    LossStreaks = 1,
    WinStreaks = 2,
    CascadeChains = 3,
    FeatureOverlaps = 4,
    JackpotEscalation = 5,
    TurboCompression = 6,
    AutoplayBurst = 7,
    LongSessionDrift = 8,
    HookBurstCollision = 9,
}

impl SimulationDomain {
    pub const COUNT: usize = 10;

    pub fn name(&self) -> &'static str {
        match self {
            Self::SpinSequences => "Spin Sequences",
            Self::LossStreaks => "Loss Streaks",
            Self::WinStreaks => "Win Streaks",
            Self::CascadeChains => "Cascade Chains",
            Self::FeatureOverlaps => "Feature Overlaps",
            Self::JackpotEscalation => "Jackpot Escalation",
            Self::TurboCompression => "Turbo Compression",
            Self::AutoplayBurst => "Autoplay Burst",
            Self::LongSessionDrift => "Long Session Drift",
            Self::HookBurstCollision => "Hook Burst/Collision",
        }
    }

    pub fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(Self::SpinSequences),
            1 => Some(Self::LossStreaks),
            2 => Some(Self::WinStreaks),
            3 => Some(Self::CascadeChains),
            4 => Some(Self::FeatureOverlaps),
            5 => Some(Self::JackpotEscalation),
            6 => Some(Self::TurboCompression),
            7 => Some(Self::AutoplayBurst),
            8 => Some(Self::LongSessionDrift),
            9 => Some(Self::HookBurstCollision),
            _ => None,
        }
    }

    pub fn all() -> &'static [SimulationDomain] {
        &[
            Self::SpinSequences,
            Self::LossStreaks,
            Self::WinStreaks,
            Self::CascadeChains,
            Self::FeatureOverlaps,
            Self::JackpotEscalation,
            Self::TurboCompression,
            Self::AutoplayBurst,
            Self::LongSessionDrift,
            Self::HookBurstCollision,
        ]
    }
}

/// Validation thresholds.
#[derive(Debug, Clone)]
pub struct ValidationThresholds {
    /// Maximum allowed energy cap. Must be ≤ 1.0.
    pub max_energy_cap: f64,
    /// Maximum allowed simultaneous voices.
    pub max_voices: u32,
    /// Maximum allowed SCI_ADV.
    pub max_sci: f64,
    /// Maximum allowed fatigue index.
    pub max_fatigue: f64,
    /// Maximum allowed escalation slope (delta per spin).
    pub max_escalation_slope: f64,
}

impl Default for ValidationThresholds {
    fn default() -> Self {
        Self {
            max_energy_cap: 1.0,
            max_voices: 40,
            max_sci: 0.85,
            max_fatigue: 0.90,
            max_escalation_slope: 5.0, // Average delta per spin; spikes are expected
        }
    }
}

/// Validation result for a single metric.
#[derive(Debug, Clone)]
pub struct MetricValidation {
    pub name: &'static str,
    pub value: f64,
    pub limit: f64,
    pub passed: bool,
}

/// Result for a single simulation domain.
#[derive(Debug, Clone)]
pub struct DomainResult {
    pub domain: SimulationDomain,
    pub passed: bool,
    pub spin_count: u32,
    pub peak_energy_cap: f64,
    pub peak_voice_count: u32,
    pub peak_sci: f64,
    pub peak_fatigue: f64,
    pub peak_escalation: f64,
    pub escalation_slope: f64,
    pub metrics: Vec<MetricValidation>,
    pub deterministic: bool,
}

impl DomainResult {
    fn validate(&mut self, thresholds: &ValidationThresholds) {
        self.metrics.clear();

        let m_energy = MetricValidation {
            name: "MaxEnergyCap",
            value: self.peak_energy_cap,
            limit: thresholds.max_energy_cap,
            passed: self.peak_energy_cap <= thresholds.max_energy_cap,
        };
        let m_voices = MetricValidation {
            name: "MaxVoices",
            value: self.peak_voice_count as f64,
            limit: thresholds.max_voices as f64,
            passed: self.peak_voice_count <= thresholds.max_voices,
        };
        let m_sci = MetricValidation {
            name: "SCI",
            value: self.peak_sci,
            limit: thresholds.max_sci,
            passed: self.peak_sci <= thresholds.max_sci,
        };
        let m_fatigue = MetricValidation {
            name: "FatigueIndex",
            value: self.peak_fatigue,
            limit: thresholds.max_fatigue,
            passed: self.peak_fatigue <= thresholds.max_fatigue,
        };
        let m_slope = MetricValidation {
            name: "EscalationSlope",
            value: self.escalation_slope,
            limit: thresholds.max_escalation_slope,
            passed: self.escalation_slope <= thresholds.max_escalation_slope,
        };

        self.passed = m_energy.passed
            && m_voices.passed
            && m_sci.passed
            && m_fatigue.passed
            && m_slope.passed
            && self.deterministic;

        self.metrics.push(m_energy);
        self.metrics.push(m_voices);
        self.metrics.push(m_sci);
        self.metrics.push(m_fatigue);
        self.metrics.push(m_slope);
    }
}

/// Full PBSE simulation result.
#[derive(Debug, Clone)]
pub struct PbseResult {
    pub domains: Vec<DomainResult>,
    pub all_passed: bool,
    pub bake_unlocked: bool,
    pub fatigue_model: FatigueModelResult,
    pub determinism_verified: bool,
    pub total_spins: u32,
}

/// 500-spin fatigue model result (PBSE-4).
#[derive(Debug, Clone)]
pub struct FatigueModelResult {
    pub fatigue_index: f64,
    pub peak_frequency: f64,
    pub harmonic_density: f64,
    pub temporal_density: f64,
    pub recovery_factor: f64,
    pub passed: bool,
    pub threshold: f64,
}

// ═════════════════════════════════════════════════════════════════════════════
// PRE-BAKE SIMULATOR
// ═════════════════════════════════════════════════════════════════════════════

/// Pre-Bake Simulation Engine.
///
/// Runs 10 deterministic stress-test domains against AUREXIS engine,
/// validates metrics, and gates BAKE on pass/fail.
pub struct PreBakeSimulator {
    config: AurexisConfig,
    thresholds: ValidationThresholds,
    last_result: Option<PbseResult>,
}

impl PreBakeSimulator {
    pub fn new() -> Self {
        Self {
            config: AurexisConfig::default(),
            thresholds: ValidationThresholds::default(),
            last_result: None,
        }
    }

    pub fn with_config(config: AurexisConfig) -> Self {
        Self {
            config,
            thresholds: ValidationThresholds::default(),
            last_result: None,
        }
    }

    pub fn set_config(&mut self, config: AurexisConfig) {
        self.config = config;
    }

    pub fn set_thresholds(&mut self, thresholds: ValidationThresholds) {
        self.thresholds = thresholds;
    }

    pub fn thresholds(&self) -> &ValidationThresholds {
        &self.thresholds
    }

    pub fn last_result(&self) -> &Option<PbseResult> {
        &self.last_result
    }

    /// Is BAKE unlocked? Only true after successful simulation.
    pub fn bake_unlocked(&self) -> bool {
        self.last_result.as_ref().is_some_and(|r| r.bake_unlocked)
    }

    /// Run full simulation across all 10 domains.
    pub fn run_full_simulation(&mut self) -> &PbseResult {
        let mut domains = Vec::with_capacity(10);
        let mut total_spins = 0u32;

        for &domain in SimulationDomain::all() {
            let result = self.run_domain(domain);
            total_spins += result.spin_count;
            domains.push(result);
        }

        // Run 500-spin fatigue model
        let fatigue_model = self.run_fatigue_model();

        // Run determinism verification
        let determinism_verified = self.verify_determinism();

        let all_passed =
            domains.iter().all(|d| d.passed) && fatigue_model.passed && determinism_verified;

        self.last_result = Some(PbseResult {
            domains,
            all_passed,
            bake_unlocked: all_passed,
            fatigue_model,
            determinism_verified,
            total_spins,
        });

        self.last_result.as_ref().unwrap()
    }

    /// Run a single simulation domain.
    pub fn run_domain(&self, domain: SimulationDomain) -> DomainResult {
        let steps = self.generate_domain_steps(domain);
        let spin_count = steps.len() as u32;

        // Run primary
        let (peaks, outputs) = self.execute_steps(&steps);

        // Run replay for determinism check
        let (_peaks2, outputs2) = self.execute_steps(&steps);

        let mut verifier = ReplayVerifier::new();
        for o in &outputs {
            verifier.record(o);
        }
        let deterministic = verifier.verify_replay(&outputs2).is_none();

        // Compute escalation slope
        let escalation_slope = Self::compute_escalation_slope(&outputs);

        let mut result = DomainResult {
            domain,
            passed: false,
            spin_count,
            peak_energy_cap: peaks.peak_energy_cap,
            peak_voice_count: peaks.peak_voice_count,
            peak_sci: peaks.peak_sci,
            peak_fatigue: peaks.peak_fatigue,
            peak_escalation: peaks.peak_escalation,
            escalation_slope,
            metrics: Vec::new(),
            deterministic,
        };

        result.validate(&self.thresholds);
        result
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DOMAIN STEP GENERATORS (PBSE-2)
    // ═══════════════════════════════════════════════════════════════════════

    fn generate_domain_steps(&self, domain: SimulationDomain) -> Vec<SimulationStep> {
        match domain {
            SimulationDomain::SpinSequences => Self::gen_spin_sequences(),
            SimulationDomain::LossStreaks => Self::gen_loss_streaks(),
            SimulationDomain::WinStreaks => Self::gen_win_streaks(),
            SimulationDomain::CascadeChains => Self::gen_cascade_chains(),
            SimulationDomain::FeatureOverlaps => Self::gen_feature_overlaps(),
            SimulationDomain::JackpotEscalation => Self::gen_jackpot_escalation(),
            SimulationDomain::TurboCompression => Self::gen_turbo_compression(),
            SimulationDomain::AutoplayBurst => Self::gen_autoplay_burst(),
            SimulationDomain::LongSessionDrift => Self::gen_long_session_drift(),
            SimulationDomain::HookBurstCollision => Self::gen_hook_burst_collision(),
        }
    }

    /// Domain 1: Spin sequences — mixed no-win, single-win, multi-win patterns.
    fn gen_spin_sequences() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(100);
        // 30 no-win → 20 small win → 10 medium win → 20 no-win → 20 big win
        for _ in 0..30 {
            steps.push(SimulationStep {
                win_multiplier: 0.0,
                ..Default::default()
            });
        }
        for _ in 0..20 {
            steps.push(SimulationStep {
                win_multiplier: 2.0,
                rms_db: -20.0,
                ..Default::default()
            });
        }
        for _ in 0..10 {
            steps.push(SimulationStep {
                win_multiplier: 10.0,
                rms_db: -16.0,
                ..Default::default()
            });
        }
        for _ in 0..20 {
            steps.push(SimulationStep {
                win_multiplier: 0.0,
                ..Default::default()
            });
        }
        for _ in 0..20 {
            steps.push(SimulationStep {
                win_multiplier: 50.0,
                rms_db: -12.0,
                hf_db: -18.0,
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 2: Loss streaks — extended periods without wins (fatigue accumulation).
    fn gen_loss_streaks() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(200);
        // 200 consecutive no-win spins
        for _ in 0..200 {
            steps.push(SimulationStep {
                win_multiplier: 0.0,
                rms_db: -22.0,
                hf_db: -28.0,
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 3: Win streaks — rapid consecutive wins (energy escalation limits).
    fn gen_win_streaks() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(80);
        // Escalating wins: 2x → 5x → 10x → 20x → 50x → 100x
        let multipliers = [2.0, 5.0, 10.0, 20.0, 50.0, 100.0];
        for &mult in &multipliers {
            for _ in 0..12 {
                steps.push(SimulationStep {
                    win_multiplier: mult,
                    rms_db: -18.0 + (mult.log2() * 2.0).min(12.0),
                    hf_db: -24.0 + (mult.log2() * 1.5).min(10.0),
                    volatility: (mult / 100.0).clamp(0.3, 0.95),
                    ..Default::default()
                });
            }
            // Brief recovery between tiers
            for _ in 0..2 {
                steps.push(SimulationStep::default());
            }
        }
        steps
    }

    /// Domain 4: Cascade chains — multi-level cascades with feature overlap.
    fn gen_cascade_chains() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(120);
        // 5 cascade sequences of increasing depth
        for cascade_depth in 1..=5 {
            // Trigger cascade
            steps.push(SimulationStep {
                win_multiplier: cascade_depth as f64 * 5.0,
                rms_db: -14.0,
                hf_db: -20.0,
                volatility: 0.6 + cascade_depth as f64 * 0.05,
                ..Default::default()
            });
            // Cascade steps (each adds more intensity)
            for step_i in 0..cascade_depth * 4 {
                steps.push(SimulationStep {
                    win_multiplier: cascade_depth as f64 * 3.0 + step_i as f64 * 0.5,
                    rms_db: -16.0 + step_i as f64 * 0.5,
                    hf_db: -22.0 + step_i as f64 * 0.3,
                    volatility: 0.7,
                    ..Default::default()
                });
            }
            // Recovery
            for _ in 0..4 {
                steps.push(SimulationStep::default());
            }
        }
        steps
    }

    /// Domain 5: Feature overlaps — features within features.
    fn gen_feature_overlaps() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(100);
        // Simulate feature entry → nested feature → exit
        for _ in 0..3 {
            // Pre-feature
            for _ in 0..5 {
                steps.push(SimulationStep::default());
            }
            // Feature entry (high intensity)
            for _ in 0..10 {
                steps.push(SimulationStep {
                    win_multiplier: 15.0,
                    rms_db: -12.0,
                    hf_db: -18.0,
                    volatility: 0.8,
                    ..Default::default()
                });
            }
            // Nested feature (even higher)
            for _ in 0..8 {
                steps.push(SimulationStep {
                    win_multiplier: 40.0,
                    rms_db: -8.0,
                    hf_db: -14.0,
                    volatility: 0.9,
                    ..Default::default()
                });
            }
            // Exit
            for _ in 0..5 {
                steps.push(SimulationStep {
                    win_multiplier: 2.0,
                    ..Default::default()
                });
            }
        }
        steps
    }

    /// Domain 6: Jackpot escalation — grand jackpot scenarios.
    fn gen_jackpot_escalation() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(60);
        // Build anticipation (increasing jackpot proximity)
        for i in 0..20 {
            steps.push(SimulationStep {
                jackpot_proximity: i as f64 / 20.0,
                rms_db: -20.0 + i as f64 * 0.5,
                hf_db: -26.0 + i as f64 * 0.3,
                volatility: 0.5 + i as f64 * 0.02,
                ..Default::default()
            });
        }
        // Jackpot trigger (max intensity)
        for _ in 0..20 {
            steps.push(SimulationStep {
                win_multiplier: 500.0,
                jackpot_proximity: 1.0,
                rms_db: -6.0,
                hf_db: -10.0,
                volatility: 0.95,
                ..Default::default()
            });
        }
        // Post-jackpot cooldown
        for _ in 0..20 {
            steps.push(SimulationStep {
                win_multiplier: 0.0,
                jackpot_proximity: 0.0,
                rms_db: -24.0,
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 7: Turbo compression — turbo mode acceleration.
    fn gen_turbo_compression() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(100);
        // Turbo = shorter elapsed_ms, denser events
        for i in 0..100 {
            let turbo_factor = 1.0 + (i as f64 / 100.0) * 3.0; // 1x → 4x speed
            steps.push(SimulationStep {
                elapsed_ms: (50.0 / turbo_factor) as u64,
                win_multiplier: if i % 5 == 0 { 5.0 } else { 0.0 },
                rms_db: -18.0,
                hf_db: -24.0,
                volatility: 0.5 + (i as f64 / 200.0),
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 8: Autoplay burst — long autoplay with varied outcomes.
    fn gen_autoplay_burst() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(150);
        // Simulate 150 spins of autoplay with pseudo-random win pattern
        // Uses deterministic pattern: small wins every ~7 spins, medium every ~25
        for i in 0..150 {
            let win = if i % 25 == 0 {
                20.0 // medium win every 25 spins
            } else if i % 7 == 0 {
                3.0 // small win every 7 spins
            } else {
                0.0
            };
            steps.push(SimulationStep {
                win_multiplier: win,
                rms_db: if win > 0.0 { -16.0 } else { -24.0 },
                hf_db: if win > 0.0 { -22.0 } else { -30.0 },
                volatility: 0.5,
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 9: Long session drift — 500+ spins tracking drift/stability.
    fn gen_long_session_drift() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(500);
        // 500 spins with gradual volatility drift and occasional spikes
        for i in 0..500 {
            let base_vol = 0.3 + (i as f64 / 1000.0) * 0.4; // Slowly increasing
            let spike = if i % 50 == 0 { 0.3 } else { 0.0 };
            let win = if i % 100 == 0 {
                30.0
            } else if i % 20 == 0 {
                3.0
            } else {
                0.0
            };

            steps.push(SimulationStep {
                win_multiplier: win,
                volatility: (base_vol + spike).min(1.0),
                rms_db: if win > 0.0 { -14.0 } else { -22.0 },
                hf_db: if win > 0.0 { -20.0 } else { -28.0 },
                ..Default::default()
            });
        }
        steps
    }

    /// Domain 10: Hook burst / frame collision — multiple events same tick.
    fn gen_hook_burst_collision() -> Vec<SimulationStep> {
        let mut steps = Vec::with_capacity(80);
        // Simulate rapid-fire events with very short elapsed_ms
        for burst in 0..8 {
            // Burst of 5 ticks at 5ms each (simulating same-frame hooks)
            for _ in 0..5 {
                steps.push(SimulationStep {
                    elapsed_ms: 5,
                    win_multiplier: burst as f64 * 5.0,
                    rms_db: -12.0,
                    hf_db: -18.0,
                    volatility: 0.8,
                    ..Default::default()
                });
            }
            // Normal timing recovery
            for _ in 0..5 {
                steps.push(SimulationStep {
                    elapsed_ms: 50,
                    win_multiplier: 0.0,
                    rms_db: -24.0,
                    ..Default::default()
                });
            }
        }
        steps
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    fn execute_steps(
        &self,
        steps: &[SimulationStep],
    ) -> (PeakMetrics, Vec<DeterministicParameterMap>) {
        let mut engine = AurexisEngine::with_config(self.config.clone());
        engine.initialize();
        engine.set_seed(0, 0, 0, 0);

        let mut outputs = Vec::with_capacity(steps.len());
        let mut peaks = PeakMetrics::default();

        for (i, step) in steps.iter().enumerate() {
            engine.set_volatility(step.volatility);
            engine.set_rtp(step.rtp);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);

            // Record spins for session memory
            let is_jackpot = step.jackpot_proximity > 0.9 && step.win_multiplier > 100.0;
            let is_feature = step.win_multiplier > 10.0;
            engine.record_spin(step.win_multiplier, is_feature, is_jackpot);

            let map = engine.compute_cloned(step.elapsed_ms);

            peaks.update(&map, i);
            outputs.push(map);
        }

        (peaks, outputs)
    }

    /// Compute escalation slope: average delta in escalation_multiplier per spin.
    /// This measures how unstable the escalation curve is across the entire domain.
    /// Individual spikes are expected (jackpot!); sustained instability is the concern.
    fn compute_escalation_slope(outputs: &[DeterministicParameterMap]) -> f64 {
        if outputs.len() < 2 {
            return 0.0;
        }
        let total_delta: f64 = outputs
            .windows(2)
            .map(|w| (w[1].escalation_multiplier - w[0].escalation_multiplier).abs())
            .sum();
        total_delta / (outputs.len() - 1) as f64
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FATIGUE MODEL (PBSE-4)
    // ═══════════════════════════════════════════════════════════════════════

    /// Run 500-spin fatigue model.
    /// FatigueIndex = (PeakFreq × HarmonicDensity × TemporalDensity) / RecoveryFactor
    fn run_fatigue_model(&self) -> FatigueModelResult {
        let steps = Self::gen_long_session_drift();
        let (_, outputs) = self.execute_steps(&steps);

        // Compute model components
        let total_spins = outputs.len() as f64;

        // PeakFrequency: ratio of spins with energy_density > 0.7
        let peak_count = outputs.iter().filter(|m| m.energy_density > 0.7).count() as f64;
        let peak_frequency = peak_count / total_spins;

        // HarmonicDensity: average harmonic_excitation across session
        let harmonic_density =
            outputs.iter().map(|m| m.harmonic_excitation).sum::<f64>() / total_spins;

        // TemporalDensity: average transient_density_per_min
        let temporal_density = outputs
            .iter()
            .map(|m| m.transient_density_per_min)
            .sum::<f64>()
            / total_spins;
        let temporal_density_norm = (temporal_density / 30.0).clamp(0.0, 1.0);

        // RecoveryFactor: derived from session_memory_sm (higher SM = better recovery)
        let avg_sm = outputs.iter().map(|m| m.session_memory_sm).sum::<f64>() / total_spins;
        let recovery_factor = avg_sm.max(0.1); // Prevent div by zero

        let fatigue_index =
            (peak_frequency * harmonic_density * temporal_density_norm) / recovery_factor;

        let threshold = self.thresholds.max_fatigue;
        FatigueModelResult {
            fatigue_index,
            peak_frequency,
            harmonic_density,
            temporal_density: temporal_density_norm,
            recovery_factor,
            passed: fatigue_index <= threshold,
            threshold,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DETERMINISM VALIDATION (PBSE-5)
    // ═══════════════════════════════════════════════════════════════════════

    /// Replay identical scenario × 2, compare all outputs.
    fn verify_determinism(&self) -> bool {
        // Use SpinSequences as canonical test scenario
        let steps = Self::gen_spin_sequences();

        let (_, outputs_a) = self.execute_steps(&steps);
        let (_, outputs_b) = self.execute_steps(&steps);

        let mut verifier = ReplayVerifier::new();
        for o in &outputs_a {
            verifier.record(o);
        }
        verifier.verify_replay(&outputs_b).is_none()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BAKE JSON OUTPUT
    // ═══════════════════════════════════════════════════════════════════════

    /// Get simulation summary JSON for bake.
    pub fn simulation_summary_json(&self) -> Result<String, serde_json::Error> {
        let result = match &self.last_result {
            Some(r) => r,
            None => {
                return serde_json::to_string_pretty(&serde_json::json!({
                    "status": "not_run",
                    "bake_unlocked": false
                }));
            }
        };

        let domains: Vec<serde_json::Value> = result
            .domains
            .iter()
            .map(|d| {
                serde_json::json!({
                    "domain": d.domain.name(),
                    "passed": d.passed,
                    "spins": d.spin_count,
                    "peak_energy_cap": format!("{:.4}", d.peak_energy_cap),
                    "peak_voices": d.peak_voice_count,
                    "peak_sci": format!("{:.4}", d.peak_sci),
                    "peak_fatigue": format!("{:.4}", d.peak_fatigue),
                    "escalation_slope": format!("{:.4}", d.escalation_slope),
                    "deterministic": d.deterministic,
                })
            })
            .collect();

        let fm = &result.fatigue_model;
        let summary = serde_json::json!({
            "status": if result.all_passed { "PASS" } else { "FAIL" },
            "bake_unlocked": result.bake_unlocked,
            "total_spins": result.total_spins,
            "determinism_verified": result.determinism_verified,
            "domains": domains,
            "fatigue_model": {
                "fatigue_index": format!("{:.4}", fm.fatigue_index),
                "peak_frequency": format!("{:.4}", fm.peak_frequency),
                "harmonic_density": format!("{:.4}", fm.harmonic_density),
                "temporal_density": format!("{:.4}", fm.temporal_density),
                "recovery_factor": format!("{:.4}", fm.recovery_factor),
                "passed": fm.passed,
                "threshold": format!("{:.2}", fm.threshold),
            },
            "thresholds": {
                "max_energy_cap": self.thresholds.max_energy_cap,
                "max_voices": self.thresholds.max_voices,
                "max_sci": self.thresholds.max_sci,
                "max_fatigue": self.thresholds.max_fatigue,
                "max_escalation_slope": self.thresholds.max_escalation_slope,
            },
        });

        serde_json::to_string_pretty(&summary)
    }

    /// Get domain names JSON for UI.
    pub fn domain_names_json() -> Result<String, serde_json::Error> {
        let names: Vec<&str> = SimulationDomain::all().iter().map(|d| d.name()).collect();
        serde_json::to_string(&names)
    }
}

impl Default for PreBakeSimulator {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// PEAK METRICS HELPER
// ═════════════════════════════════════════════════════════════════════════════

#[derive(Debug, Default)]
struct PeakMetrics {
    peak_energy_cap: f64,
    peak_voice_count: u32,
    peak_sci: f64,
    peak_fatigue: f64,
    peak_escalation: f64,
}

impl PeakMetrics {
    fn update(&mut self, map: &DeterministicParameterMap, _tick: usize) {
        self.peak_energy_cap = self.peak_energy_cap.max(map.energy_overall_cap);
        self.peak_voice_count = self.peak_voice_count.max(map.voice_budget_max);
        self.peak_sci = self.peak_sci.max(map.sci_adv);
        self.peak_fatigue = self.peak_fatigue.max(map.fatigue_index);
        self.peak_escalation = self.peak_escalation.max(map.escalation_multiplier);
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS (PBSE-7)
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_domain_count() {
        assert_eq!(SimulationDomain::COUNT, 10);
        assert_eq!(SimulationDomain::all().len(), 10);
    }

    #[test]
    fn test_domain_names() {
        assert_eq!(SimulationDomain::SpinSequences.name(), "Spin Sequences");
        assert_eq!(
            SimulationDomain::HookBurstCollision.name(),
            "Hook Burst/Collision"
        );
    }

    #[test]
    fn test_domain_from_index() {
        for i in 0..10 {
            assert!(SimulationDomain::from_index(i).is_some());
        }
        assert!(SimulationDomain::from_index(10).is_none());
    }

    #[test]
    fn test_run_full_simulation() {
        let mut sim = PreBakeSimulator::new();
        let result = sim.run_full_simulation();
        assert_eq!(result.domains.len(), 10);
        assert!(result.total_spins > 0);
    }

    #[test]
    fn test_all_domains_produce_steps() {
        let sim = PreBakeSimulator::new();
        for &domain in SimulationDomain::all() {
            let steps = sim.generate_domain_steps(domain);
            assert!(!steps.is_empty(), "Domain {:?} produced no steps", domain);
        }
    }

    #[test]
    fn test_spin_sequences_domain() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::SpinSequences);
        assert_eq!(result.spin_count, 100);
        assert!(result.deterministic, "Spin sequences must be deterministic");
        assert!(!result.metrics.is_empty());
    }

    #[test]
    fn test_loss_streaks_domain() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::LossStreaks);
        assert_eq!(result.spin_count, 200);
        assert!(result.deterministic);
    }

    #[test]
    fn test_win_streaks_domain() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::WinStreaks);
        assert!(
            result.peak_escalation > 1.0,
            "Win streaks should cause escalation"
        );
    }

    #[test]
    fn test_jackpot_escalation_domain() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::JackpotEscalation);
        assert!(
            result.peak_escalation > 1.0,
            "Jackpot should cause high escalation"
        );
    }

    #[test]
    fn test_long_session_drift_500_spins() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::LongSessionDrift);
        assert_eq!(result.spin_count, 500);
        assert!(
            result.peak_fatigue > 0.0,
            "500 spins should accumulate fatigue"
        );
    }

    #[test]
    fn test_hook_burst_collision() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::HookBurstCollision);
        assert!(result.deterministic, "Hook bursts must be deterministic");
    }

    #[test]
    fn test_fatigue_model() {
        let sim = PreBakeSimulator::new();
        let fm = sim.run_fatigue_model();
        assert!(
            fm.fatigue_index >= 0.0,
            "Fatigue index must be non-negative"
        );
        assert!(fm.peak_frequency >= 0.0 && fm.peak_frequency <= 1.0);
        assert!(fm.recovery_factor > 0.0);
    }

    #[test]
    fn test_determinism_verification() {
        let sim = PreBakeSimulator::new();
        assert!(sim.verify_determinism(), "Engine must be deterministic");
    }

    #[test]
    fn test_bake_gate() {
        let mut sim = PreBakeSimulator::new();
        assert!(
            !sim.bake_unlocked(),
            "Bake should be locked before simulation"
        );

        let result = sim.run_full_simulation();

        // Debug: report which domains failed
        for d in &result.domains {
            if !d.passed {
                eprintln!(
                    "FAIL: {} — energy={:.4} voices={} sci={:.4} fatigue={:.4} slope={:.4} det={}",
                    d.domain.name(),
                    d.peak_energy_cap,
                    d.peak_voice_count,
                    d.peak_sci,
                    d.peak_fatigue,
                    d.escalation_slope,
                    d.deterministic
                );
                for m in &d.metrics {
                    if !m.passed {
                        eprintln!(
                            "  metric {} = {:.4} > limit {:.4}",
                            m.name, m.value, m.limit
                        );
                    }
                }
            }
        }
        if !result.fatigue_model.passed {
            eprintln!(
                "FAIL: fatigue_model index={:.4} > threshold={:.4}",
                result.fatigue_model.fatigue_index, result.fatigue_model.threshold
            );
        }

        assert!(
            sim.bake_unlocked(),
            "Bake should be unlocked after passing simulation"
        );
    }

    #[test]
    fn test_validation_metrics() {
        let sim = PreBakeSimulator::new();
        let result = sim.run_domain(SimulationDomain::SpinSequences);
        assert_eq!(result.metrics.len(), 5);

        let metric_names: Vec<&str> = result.metrics.iter().map(|m| m.name).collect();
        assert!(metric_names.contains(&"MaxEnergyCap"));
        assert!(metric_names.contains(&"MaxVoices"));
        assert!(metric_names.contains(&"SCI"));
        assert!(metric_names.contains(&"FatigueIndex"));
        assert!(metric_names.contains(&"EscalationSlope"));
    }

    #[test]
    fn test_escalation_slope_computation() {
        let outputs = vec![
            {
                let mut m = DeterministicParameterMap::default();
                m.escalation_multiplier = 1.0;
                m
            },
            {
                let mut m = DeterministicParameterMap::default();
                m.escalation_multiplier = 1.1;
                m
            },
            {
                let mut m = DeterministicParameterMap::default();
                m.escalation_multiplier = 1.05;
                m
            },
        ];
        let slope = PreBakeSimulator::compute_escalation_slope(&outputs);
        // Average of |0.1| and |0.05| = 0.075
        assert!(
            (slope - 0.075).abs() < 0.001,
            "Slope should be ~0.075, got {}",
            slope
        );
    }

    #[test]
    fn test_custom_thresholds_fail() {
        let mut sim = PreBakeSimulator::new();
        // Set impossibly strict thresholds
        sim.set_thresholds(ValidationThresholds {
            max_energy_cap: 0.01,
            max_voices: 1,
            max_sci: 0.001,
            max_fatigue: 0.001,
            max_escalation_slope: 0.0001,
        });
        sim.run_full_simulation();
        assert!(
            !sim.bake_unlocked(),
            "Strict thresholds should cause bake lock"
        );

        // Verify at least some domains failed
        let result = sim.last_result().as_ref().unwrap();
        let failed_count = result.domains.iter().filter(|d| !d.passed).count();
        assert!(
            failed_count > 0,
            "Should have failing domains with strict thresholds"
        );
    }

    #[test]
    fn test_simulation_summary_json() {
        let mut sim = PreBakeSimulator::new();
        sim.run_full_simulation();
        let json = sim.simulation_summary_json().unwrap();
        assert!(json.contains("\"status\""));
        assert!(json.contains("\"bake_unlocked\""));
        assert!(json.contains("\"domains\""));
        assert!(json.contains("\"fatigue_model\""));
    }

    #[test]
    fn test_domain_names_json() {
        let json = PreBakeSimulator::domain_names_json().unwrap();
        assert!(json.contains("Spin Sequences"));
        assert!(json.contains("Hook Burst/Collision"));
    }
}
