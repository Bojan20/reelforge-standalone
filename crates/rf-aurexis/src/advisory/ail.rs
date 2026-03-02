//! AIL: Authoring Intelligence Layer
//!
//! Advisory system operating post-PBSE, pre-BAKE. Cannot block BAKE —
//! only flags/warns/recommends. Analyzes game audio configuration against
//! best practices across 10 analysis domains.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §9

use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::core::parameter_map::DeterministicParameterMap;
use crate::qa::pbse::PbseResult;
use crate::qa::simulation::SimulationStep;

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// 10 AIL analysis domains.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum AilDomain {
    HookFrequency = 0,
    VolatilityPattern = 1,
    CascadeDensity = 2,
    FeatureOverlap = 3,
    EmotionalCurve = 4,
    EnergyDistribution = 5,
    VoiceUtilization = 6,
    SpectralOverlap = 7,
    FatigueProjection = 8,
    SessionDrift = 9,
}

impl AilDomain {
    pub const COUNT: usize = 10;

    pub fn name(&self) -> &'static str {
        match self {
            Self::HookFrequency => "Hook Frequency",
            Self::VolatilityPattern => "Volatility Pattern",
            Self::CascadeDensity => "Cascade Density",
            Self::FeatureOverlap => "Feature Overlap",
            Self::EmotionalCurve => "Emotional Curve",
            Self::EnergyDistribution => "Energy Distribution",
            Self::VoiceUtilization => "Voice Utilization",
            Self::SpectralOverlap => "Spectral Overlap",
            Self::FatigueProjection => "Fatigue Projection",
            Self::SessionDrift => "Session Drift",
        }
    }

    pub fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(Self::HookFrequency),
            1 => Some(Self::VolatilityPattern),
            2 => Some(Self::CascadeDensity),
            3 => Some(Self::FeatureOverlap),
            4 => Some(Self::EmotionalCurve),
            5 => Some(Self::EnergyDistribution),
            6 => Some(Self::VoiceUtilization),
            7 => Some(Self::SpectralOverlap),
            8 => Some(Self::FatigueProjection),
            9 => Some(Self::SessionDrift),
            _ => None,
        }
    }

    pub fn all() -> &'static [AilDomain] {
        &[
            Self::HookFrequency,
            Self::VolatilityPattern,
            Self::CascadeDensity,
            Self::FeatureOverlap,
            Self::EmotionalCurve,
            Self::EnergyDistribution,
            Self::VoiceUtilization,
            Self::SpectralOverlap,
            Self::FatigueProjection,
            Self::SessionDrift,
        ]
    }
}

/// Overall AIL status.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AilStatus {
    Excellent,
    Good,
    Fair,
    Poor,
    Critical,
}

impl AilStatus {
    pub fn from_score(score: f64) -> Self {
        if score >= 90.0 {
            Self::Excellent
        } else if score >= 75.0 {
            Self::Good
        } else if score >= 60.0 {
            Self::Fair
        } else if score >= 40.0 {
            Self::Poor
        } else {
            Self::Critical
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Excellent => "EXCELLENT",
            Self::Good => "GOOD",
            Self::Fair => "FAIR",
            Self::Poor => "POOR",
            Self::Critical => "CRITICAL",
        }
    }
}

/// Recommendation severity level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum RecommendationLevel {
    Info,
    Warning,
    Critical,
}

impl RecommendationLevel {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Info => "INFO",
            Self::Warning => "WARNING",
            Self::Critical => "CRITICAL",
        }
    }
}

/// Effort estimate for a recommendation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffortEstimate {
    Trivial,
    Low,
    Medium,
    High,
}

impl EffortEstimate {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Trivial => "TRIVIAL",
            Self::Low => "LOW",
            Self::Medium => "MEDIUM",
            Self::High => "HIGH",
        }
    }
}

/// AIL Score (0–100).
#[derive(Debug, Clone, Copy)]
pub struct AilScore {
    pub value: f64,
    pub status: AilStatus,
}

/// Per-domain analysis result.
#[derive(Debug, Clone)]
pub struct DomainAnalysis {
    pub domain: AilDomain,
    pub score: f64,
    pub risk: f64,
    pub details: String,
}

/// Fatigue analysis.
#[derive(Debug, Clone)]
pub struct FatigueAnalysis {
    pub fatigue_score: f64,
    pub peak_frequency: f64,
    pub harmonic_density: f64,
    pub temporal_density: f64,
    pub recovery_factor: f64,
    pub risk_level: &'static str,
}

/// Voice efficiency metrics.
#[derive(Debug, Clone)]
pub struct VoiceEfficiency {
    pub avg_voices: f64,
    pub peak_voices: u32,
    pub budget_cap: u32,
    pub utilization_pct: f64,
    pub efficiency_score: f64,
}

/// Spectral clarity analysis.
#[derive(Debug, Clone)]
pub struct SpectralClarityAnalysis {
    pub sci_advanced: f64,
    pub sci_limit: f64,
    pub clarity_score: f64,
    pub overlap_count: u32,
}

/// Volatility alignment analysis.
#[derive(Debug, Clone)]
pub struct VolatilityAlignment {
    pub alignment_score: f64,
    pub energy_variance: f64,
    pub escalation_range: f64,
}

/// Single recommendation.
#[derive(Debug, Clone)]
pub struct AilRecommendation {
    pub rank: u32,
    pub level: RecommendationLevel,
    pub domain: AilDomain,
    pub title: String,
    pub description: String,
    pub impact_score: f64,
    pub effort: EffortEstimate,
}

/// Complete AIL report.
#[derive(Debug, Clone)]
pub struct AilReport {
    pub score: AilScore,
    pub domain_analyses: Vec<DomainAnalysis>,
    pub recommendations: Vec<AilRecommendation>,
    pub fatigue: FatigueAnalysis,
    pub voice_efficiency: VoiceEfficiency,
    pub spectral_clarity: SpectralClarityAnalysis,
    pub volatility_alignment: VolatilityAlignment,
    pub critical_count: u32,
    pub warning_count: u32,
    pub info_count: u32,
    pub simulation_spins: u32,
    pub pbse_passed: bool,
}

// ═════════════════════════════════════════════════════════════════════════════
// AUTHORING INTELLIGENCE
// ═════════════════════════════════════════════════════════════════════════════

/// Authoring Intelligence Layer.
///
/// Advisory analysis post-PBSE. Cannot block BAKE — only flags/warns/recommends.
pub struct AuthoringIntelligence {
    config: AurexisConfig,
    last_report: Option<AilReport>,
}

impl AuthoringIntelligence {
    pub fn new() -> Self {
        Self {
            config: AurexisConfig::default(),
            last_report: None,
        }
    }

    pub fn with_config(config: AurexisConfig) -> Self {
        Self {
            config,
            last_report: None,
        }
    }

    /// Run full AIL analysis using PBSE results and fresh simulation data.
    pub fn analyze(&mut self, pbse_result: Option<&PbseResult>) -> AilReport {
        // Run a 500-spin simulation for analysis data
        let steps = gen_analysis_steps(500);
        let outputs = self.execute_steps(&steps);

        // Run all 10 domain analyses
        let mut domain_analyses = Vec::with_capacity(AilDomain::COUNT);
        let mut recommendations = Vec::new();

        // Domain 0: Hook Frequency
        let hook_analysis = analyze_hook_frequency(&steps);
        maybe_recommend(
            &mut recommendations,
            &hook_analysis,
            "Hook burst density elevated",
            "Multiple high-intensity events in rapid succession may cause voice contention",
            EffortEstimate::Medium,
        );
        domain_analyses.push(hook_analysis);

        // Domain 1: Volatility Pattern
        let (volatility_analysis, vol_align) = analyze_volatility_pattern(&outputs);
        maybe_recommend(
            &mut recommendations,
            &volatility_analysis,
            "Volatility pattern mismatch",
            "Energy variance doesn't align with expected slot profile characteristics",
            EffortEstimate::Low,
        );
        domain_analyses.push(volatility_analysis);

        // Domain 2: Cascade Density
        let cascade_analysis = analyze_cascade_density(&steps);
        maybe_recommend(
            &mut recommendations,
            &cascade_analysis,
            "Cascade density imbalance",
            "Audio escalation may not match cascade pattern depth distribution",
            EffortEstimate::Medium,
        );
        domain_analyses.push(cascade_analysis);

        // Domain 3: Feature Overlap
        let overlap_analysis = analyze_feature_overlap(&steps);
        maybe_recommend(
            &mut recommendations,
            &overlap_analysis,
            "Concurrent feature intensity high",
            "Simultaneous high-priority events may exceed voice and spectral budgets",
            EffortEstimate::High,
        );
        domain_analyses.push(overlap_analysis);

        // Domain 4: Emotional Curve
        let emotional_analysis = analyze_emotional_curve(&outputs);
        maybe_recommend(
            &mut recommendations,
            &emotional_analysis,
            "Emotional curve instability",
            "Erratic escalation transitions reduce player immersion quality",
            EffortEstimate::Medium,
        );
        domain_analyses.push(emotional_analysis);

        // Domain 5: Energy Distribution
        let energy_analysis = analyze_energy_distribution(&outputs);
        maybe_recommend(
            &mut recommendations,
            &energy_analysis,
            "Energy domain imbalance",
            "Energy concentrated in too few domains; diversify for richer audio",
            EffortEstimate::Low,
        );
        domain_analyses.push(energy_analysis);

        // Domain 6: Voice Utilization
        let (voice_analysis, voice_eff) = analyze_voice_utilization(&outputs);
        maybe_recommend(
            &mut recommendations,
            &voice_analysis,
            "Voice budget utilization concern",
            "Voice allocation may be underutilized or near capacity limits",
            EffortEstimate::Trivial,
        );
        domain_analyses.push(voice_analysis);

        // Domain 7: Spectral Overlap
        let (spectral_analysis, spectral_clarity) = analyze_spectral_overlap(&outputs);
        maybe_recommend(
            &mut recommendations,
            &spectral_analysis,
            "Spectral collision risk",
            "Frequency band overlap may cause masking artifacts in dense scenes",
            EffortEstimate::Medium,
        );
        domain_analyses.push(spectral_analysis);

        // Domain 8: Fatigue Projection
        let (fatigue_analysis, fatigue_result) = analyze_fatigue_projection(&outputs);
        maybe_recommend(
            &mut recommendations,
            &fatigue_analysis,
            "Listener fatigue risk",
            "Prolonged high-intensity audio may cause listener fatigue over time",
            EffortEstimate::Medium,
        );
        domain_analyses.push(fatigue_analysis);

        // Domain 9: Session Drift
        let drift_analysis = analyze_session_drift(&outputs);
        maybe_recommend(
            &mut recommendations,
            &drift_analysis,
            "Session energy drift detected",
            "Sustained energy creep or emotional flatness over extended play session",
            EffortEstimate::Low,
        );
        domain_analyses.push(drift_analysis);

        // Sort recommendations by impact score (descending)
        recommendations.sort_by(|a, b| {
            b.impact_score
                .partial_cmp(&a.impact_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        for (i, rec) in recommendations.iter_mut().enumerate() {
            rec.rank = (i + 1) as u32;
        }

        // Compute overall AIL Score: 100 × (1.0 - avg_risk)
        let avg_risk =
            domain_analyses.iter().map(|d| d.risk).sum::<f64>() / domain_analyses.len() as f64;
        let score_value = (100.0 * (1.0 - avg_risk)).clamp(0.0, 100.0);
        let score = AilScore {
            value: score_value,
            status: AilStatus::from_score(score_value),
        };

        let critical_count = recommendations
            .iter()
            .filter(|r| r.level == RecommendationLevel::Critical)
            .count() as u32;
        let warning_count = recommendations
            .iter()
            .filter(|r| r.level == RecommendationLevel::Warning)
            .count() as u32;
        let info_count = recommendations
            .iter()
            .filter(|r| r.level == RecommendationLevel::Info)
            .count() as u32;

        let pbse_passed = pbse_result.map_or(false, |r| r.all_passed);

        let report = AilReport {
            score,
            domain_analyses,
            recommendations,
            fatigue: fatigue_result,
            voice_efficiency: voice_eff,
            spectral_clarity,
            volatility_alignment: vol_align,
            critical_count,
            warning_count,
            info_count,
            simulation_spins: 500,
            pbse_passed,
        };

        self.last_report = Some(report.clone());
        report
    }

    /// Get the last analysis report.
    pub fn last_report(&self) -> Option<&AilReport> {
        self.last_report.as_ref()
    }

    /// Generate JSON report string.
    pub fn report_json(&self) -> Result<String, String> {
        let report = self.last_report.as_ref().ok_or("No AIL report available")?;
        report_to_json(report)
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.last_report = None;
    }

    /// Execute simulation steps through AUREXIS engine.
    fn execute_steps(&self, steps: &[SimulationStep]) -> Vec<DeterministicParameterMap> {
        let mut engine = AurexisEngine::with_config(self.config.clone());
        engine.initialize();
        engine.set_seed(0, 0, 0, 0);

        let mut outputs = Vec::with_capacity(steps.len());

        for step in steps {
            engine.set_volatility(step.volatility);
            engine.set_rtp(step.rtp);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);

            let is_jackpot = step.jackpot_proximity > 0.9 && step.win_multiplier > 100.0;
            let is_feature = step.win_multiplier > 10.0;
            engine.record_spin(step.win_multiplier, is_feature, is_jackpot);

            let map = engine.compute_cloned(step.elapsed_ms);
            outputs.push(map);
        }

        outputs
    }
}

impl Default for AuthoringIntelligence {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// RECOMMENDATION HELPER
// ═════════════════════════════════════════════════════════════════════════════

fn level_from_risk(risk: f64) -> RecommendationLevel {
    if risk >= 0.7 {
        RecommendationLevel::Critical
    } else if risk >= 0.4 {
        RecommendationLevel::Warning
    } else {
        RecommendationLevel::Info
    }
}

fn maybe_recommend(
    recs: &mut Vec<AilRecommendation>,
    analysis: &DomainAnalysis,
    title: &str,
    description: &str,
    effort: EffortEstimate,
) {
    if analysis.risk > 0.3 {
        recs.push(AilRecommendation {
            rank: 0, // will be re-ranked later
            level: level_from_risk(analysis.risk),
            domain: analysis.domain,
            title: title.into(),
            description: description.into(),
            impact_score: analysis.risk * 100.0,
            effort,
        });
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// DOMAIN ANALYSIS FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════════

/// Domain 0: Hook Frequency Analysis
/// Detects unhealthy hook burst patterns (high win_multiplier clusters).
fn analyze_hook_frequency(steps: &[SimulationStep]) -> DomainAnalysis {
    let total = steps.len();
    let mut burst_count = 0u32;
    let mut consecutive_high = 0u32;
    let mut max_consecutive = 0u32;

    for step in steps {
        if step.win_multiplier > 10.0 || step.jackpot_proximity > 0.5 {
            consecutive_high += 1;
            if consecutive_high > 3 {
                burst_count += 1;
            }
        } else {
            max_consecutive = max_consecutive.max(consecutive_high);
            consecutive_high = 0;
        }
    }
    max_consecutive = max_consecutive.max(consecutive_high);

    let burst_ratio = if total > 0 {
        burst_count as f64 / total as f64
    } else {
        0.0
    };
    let risk = (burst_ratio * 5.0).clamp(0.0, 1.0);
    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::HookFrequency,
        score,
        risk,
        details: format!(
            "total={} bursts={} max_consecutive={}",
            total, burst_count, max_consecutive
        ),
    }
}

/// Domain 1: Volatility Pattern Detection
fn analyze_volatility_pattern(
    outputs: &[DeterministicParameterMap],
) -> (DomainAnalysis, VolatilityAlignment) {
    if outputs.is_empty() {
        let analysis = DomainAnalysis {
            domain: AilDomain::VolatilityPattern,
            score: 100.0,
            risk: 0.0,
            details: "No data".into(),
        };
        let align = VolatilityAlignment {
            alignment_score: 100.0,
            energy_variance: 0.0,
            escalation_range: 0.0,
        };
        return (analysis, align);
    }

    let energies: Vec<f64> = outputs.iter().map(|o| o.energy_density).collect();
    let mean = energies.iter().sum::<f64>() / energies.len() as f64;
    let variance = energies.iter().map(|e| (e - mean).powi(2)).sum::<f64>() / energies.len() as f64;

    let esc_values: Vec<f64> = outputs.iter().map(|o| o.escalation_multiplier).collect();
    let esc_min = esc_values.iter().cloned().fold(f64::MAX, f64::min);
    let esc_max = esc_values.iter().cloned().fold(f64::MIN, f64::max);
    let esc_range = esc_max - esc_min;

    // Low variance + high range = pattern mismatch
    let risk = if variance < 0.01 && esc_range > 2.0 {
        0.5
    } else if variance < 0.005 {
        0.3
    } else {
        (0.1_f64).max(1.0 - variance.sqrt() * 3.0).clamp(0.0, 0.5)
    };

    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    let analysis = DomainAnalysis {
        domain: AilDomain::VolatilityPattern,
        score,
        risk,
        details: format!("energy_variance={:.4} esc_range={:.2}", variance, esc_range),
    };

    let align = VolatilityAlignment {
        alignment_score: score,
        energy_variance: variance,
        escalation_range: esc_range,
    };

    (analysis, align)
}

/// Domain 2: Cascade Density Analysis
fn analyze_cascade_density(steps: &[SimulationStep]) -> DomainAnalysis {
    // Cascades are simulated via consecutive high-win_multiplier steps with increasing intensity
    let mut cascade_count = 0u32;
    let mut in_cascade = false;
    let mut max_depth = 0u32;
    let mut current_depth = 0u32;

    for i in 1..steps.len() {
        if steps[i].win_multiplier > steps[i - 1].win_multiplier && steps[i].win_multiplier > 5.0 {
            if !in_cascade {
                cascade_count += 1;
                in_cascade = true;
                current_depth = 1;
            }
            current_depth += 1;
        } else {
            max_depth = max_depth.max(current_depth);
            in_cascade = false;
            current_depth = 0;
        }
    }
    max_depth = max_depth.max(current_depth);

    let total = steps.len().max(1);
    let cascade_pct = cascade_count as f64 / total as f64;

    let risk = if cascade_pct > 0.3 {
        ((cascade_pct - 0.3) * 3.0).clamp(0.0, 0.8)
    } else if cascade_count == 0 {
        0.15
    } else {
        0.05
    };

    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::CascadeDensity,
        score,
        risk,
        details: format!(
            "cascades={} max_depth={} cascade_pct={:.1}%",
            cascade_count,
            max_depth,
            cascade_pct * 100.0
        ),
    }
}

/// Domain 3: Feature Overlap Intensity
fn analyze_feature_overlap(steps: &[SimulationStep]) -> DomainAnalysis {
    let mut concurrent_highs = 0u32;
    let mut max_concurrent = 0u32;
    let mut current_streak = 0u32;

    for step in steps {
        let is_high = step.win_multiplier > 10.0 || step.jackpot_proximity > 0.7;
        if is_high {
            current_streak += 1;
            max_concurrent = max_concurrent.max(current_streak);
        } else {
            if current_streak > 2 {
                concurrent_highs += 1;
            }
            current_streak = 0;
        }
    }

    let risk = (concurrent_highs as f64 * 0.05 + if max_concurrent > 10 { 0.3 } else { 0.0 })
        .clamp(0.0, 1.0);
    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::FeatureOverlap,
        score,
        risk,
        details: format!(
            "overlap_events={} max_concurrent={}",
            concurrent_highs, max_concurrent
        ),
    }
}

/// Domain 4: Emotional Curve Stability
fn analyze_emotional_curve(outputs: &[DeterministicParameterMap]) -> DomainAnalysis {
    if outputs.len() < 2 {
        return DomainAnalysis {
            domain: AilDomain::EmotionalCurve,
            score: 100.0,
            risk: 0.0,
            details: "Insufficient data".into(),
        };
    }

    let mut total_delta = 0.0_f64;
    let mut max_delta = 0.0_f64;
    let mut jump_count = 0u32;

    for i in 1..outputs.len() {
        let delta = (outputs[i].escalation_multiplier - outputs[i - 1].escalation_multiplier).abs();
        total_delta += delta;
        max_delta = max_delta.max(delta);
        if delta > 5.0 {
            jump_count += 1;
        }
    }

    let avg_delta = total_delta / (outputs.len() - 1) as f64;
    let smoothness = 1.0 / (1.0 + avg_delta);

    let risk = if jump_count > 20 {
        0.7
    } else if jump_count > 10 {
        0.4
    } else if max_delta > 50.0 {
        0.3
    } else {
        (1.0 - smoothness).clamp(0.0, 0.3)
    };

    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::EmotionalCurve,
        score,
        risk,
        details: format!(
            "avg_delta={:.3} max_delta={:.1} jumps={} smoothness={:.3}",
            avg_delta, max_delta, jump_count, smoothness
        ),
    }
}

/// Domain 5: Energy Distribution
fn analyze_energy_distribution(outputs: &[DeterministicParameterMap]) -> DomainAnalysis {
    if outputs.is_empty() {
        return DomainAnalysis {
            domain: AilDomain::EnergyDistribution,
            score: 100.0,
            risk: 0.0,
            details: "No data".into(),
        };
    }

    let n = outputs.len() as f64;

    // 5 energy dimensions from output fields
    let avg_energy = outputs.iter().map(|o| o.energy_density).sum::<f64>() / n;
    let avg_transient = outputs.iter().map(|o| o.transient_sharpness).sum::<f64>() / n;
    let avg_width = outputs.iter().map(|o| o.stereo_width).sum::<f64>() / n;
    let avg_harmonic = outputs.iter().map(|o| o.harmonic_excitation).sum::<f64>() / n;
    let avg_reverb = outputs
        .iter()
        .map(|o| (o.reverb_send_bias + 1.0) / 2.0)
        .sum::<f64>()
        / n;

    let domains = [
        avg_energy,
        avg_transient / 2.0,
        avg_width / 2.0,
        avg_harmonic / 2.0,
        avg_reverb,
    ];
    let domain_mean = domains.iter().sum::<f64>() / domains.len() as f64;
    let domain_variance = domains
        .iter()
        .map(|d| (d - domain_mean).powi(2))
        .sum::<f64>()
        / domains.len() as f64;

    let imbalance = domain_variance.sqrt();
    let risk = (imbalance * 2.0).clamp(0.0, 0.8);
    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::EnergyDistribution,
        score,
        risk,
        details: format!(
            "imbalance={:.4} E={:.2} T={:.2} W={:.2} H={:.2} R={:.2}",
            imbalance, avg_energy, avg_transient, avg_width, avg_harmonic, avg_reverb
        ),
    }
}

/// Domain 6: Voice Utilization
fn analyze_voice_utilization(
    outputs: &[DeterministicParameterMap],
) -> (DomainAnalysis, VoiceEfficiency) {
    let budget = 48u32;

    let voice_estimates: Vec<u32> = outputs
        .iter()
        .map(|o| {
            let base = o.center_occupancy;
            let from_energy = (o.energy_density * 8.0) as u32;
            base + from_energy
        })
        .collect();

    let avg_voices = if voice_estimates.is_empty() {
        0.0
    } else {
        voice_estimates.iter().sum::<u32>() as f64 / voice_estimates.len() as f64
    };
    let peak_voices = voice_estimates.iter().cloned().max().unwrap_or(0);

    let utilization = if budget > 0 {
        avg_voices / budget as f64
    } else {
        0.0
    };
    let efficiency = utilization.clamp(0.0, 1.0);

    let risk: f64 = if utilization > 0.95 {
        0.7
    } else if utilization > 0.9 {
        0.5
    } else if utilization < 0.2 {
        0.3
    } else {
        0.1
    };

    let score = ((1.0 - risk) * 100.0_f64).clamp(0.0, 100.0);

    let analysis = DomainAnalysis {
        domain: AilDomain::VoiceUtilization,
        score,
        risk,
        details: format!(
            "avg={:.1} peak={} budget={} util={:.1}%",
            avg_voices,
            peak_voices,
            budget,
            utilization * 100.0
        ),
    };

    let eff = VoiceEfficiency {
        avg_voices,
        peak_voices,
        budget_cap: budget,
        utilization_pct: utilization * 100.0,
        efficiency_score: efficiency * 100.0,
    };

    (analysis, eff)
}

/// Domain 7: Spectral Overlap Risk
fn analyze_spectral_overlap(
    outputs: &[DeterministicParameterMap],
) -> (DomainAnalysis, SpectralClarityAnalysis) {
    if outputs.is_empty() {
        let analysis = DomainAnalysis {
            domain: AilDomain::SpectralOverlap,
            score: 100.0,
            risk: 0.0,
            details: "No data".into(),
        };
        let clarity = SpectralClarityAnalysis {
            sci_advanced: 0.0,
            sci_limit: 0.85,
            clarity_score: 100.0,
            overlap_count: 0,
        };
        return (analysis, clarity);
    }

    // Estimate SCI from harmonic excitation × energy density × occupancy
    let sci_estimates: Vec<f64> = outputs
        .iter()
        .map(|o| {
            let harmonic = (o.harmonic_excitation - 1.0).max(0.0);
            let energy = o.energy_density;
            let occupancy_factor = (o.center_occupancy as f64 / 10.0).min(1.0);
            (harmonic * energy * occupancy_factor * 2.0).clamp(0.0, 1.0)
        })
        .collect();

    let avg_sci = sci_estimates.iter().sum::<f64>() / sci_estimates.len() as f64;
    let max_sci = sci_estimates.iter().cloned().fold(0.0_f64, f64::max);
    let overlap_count = sci_estimates.iter().filter(|s| **s > 0.6).count() as u32;

    // Per spec: < 0.6 = Excellent, 0.6-0.75 = Good, 0.75-0.85 = Fair, > 0.85 = Poor
    let risk: f64 = if avg_sci > 0.85 {
        0.8
    } else if avg_sci > 0.75 {
        0.5
    } else if avg_sci > 0.6 {
        0.3
    } else {
        0.1
    };

    let score = ((1.0 - risk) * 100.0_f64).clamp(0.0, 100.0);
    let clarity_score = ((1.0 - avg_sci / 0.85) * 100.0_f64).clamp(0.0, 100.0);

    let analysis = DomainAnalysis {
        domain: AilDomain::SpectralOverlap,
        score,
        risk,
        details: format!(
            "avg_sci={:.4} max_sci={:.4} overlaps={}",
            avg_sci, max_sci, overlap_count
        ),
    };

    let clarity = SpectralClarityAnalysis {
        sci_advanced: avg_sci,
        sci_limit: 0.85,
        clarity_score,
        overlap_count,
    };

    (analysis, clarity)
}

/// Domain 8: Fatigue Projection
fn analyze_fatigue_projection(
    outputs: &[DeterministicParameterMap],
) -> (DomainAnalysis, FatigueAnalysis) {
    if outputs.is_empty() {
        let analysis = DomainAnalysis {
            domain: AilDomain::FatigueProjection,
            score: 100.0,
            risk: 0.0,
            details: "No data".into(),
        };
        let fatigue = FatigueAnalysis {
            fatigue_score: 0.0,
            peak_frequency: 0.0,
            harmonic_density: 0.0,
            temporal_density: 0.0,
            recovery_factor: 1.0,
            risk_level: "LOW",
        };
        return (analysis, fatigue);
    }

    let n = outputs.len() as f64;

    // Peak frequency: how often energy exceeds 0.7
    let peak_count = outputs.iter().filter(|o| o.energy_density > 0.7).count();
    let peak_frequency = peak_count as f64 / n;

    // Harmonic density: average harmonic excitation
    let harmonic_density = outputs.iter().map(|o| o.harmonic_excitation).sum::<f64>() / n;

    // Temporal density: rate of significant energy changes
    let mut change_count = 0u32;
    for i in 1..outputs.len() {
        let delta = (outputs[i].energy_density - outputs[i - 1].energy_density).abs();
        if delta > 0.1 {
            change_count += 1;
        }
    }
    let temporal_density = change_count as f64 / n;

    // Recovery factor: proportion of low-energy frames
    let recovery_frames = outputs.iter().filter(|o| o.energy_density < 0.3).count();
    let recovery_factor = (recovery_frames as f64 / n).max(0.01);

    // FatigueIndex = (PeakFrequency × HarmonicDensity × TemporalDensity) / RecoveryFactor
    let fatigue_index = (peak_frequency * harmonic_density * temporal_density) / recovery_factor;
    let fatigue_score = (fatigue_index * 100.0).clamp(0.0, 100.0);

    let risk_level = if fatigue_score > 70.0 {
        "CRITICAL"
    } else if fatigue_score > 50.0 {
        "HIGH"
    } else if fatigue_score > 30.0 {
        "MODERATE"
    } else {
        "LOW"
    };

    let risk = (fatigue_score / 100.0).clamp(0.0, 1.0);
    let score = ((1.0 - risk) * 100.0).clamp(0.0, 100.0);

    let analysis = DomainAnalysis {
        domain: AilDomain::FatigueProjection,
        score,
        risk,
        details: format!(
            "fatigue_idx={:.4} PF={:.3} HD={:.3} TD={:.3} RF={:.3}",
            fatigue_index, peak_frequency, harmonic_density, temporal_density, recovery_factor
        ),
    };

    let fatigue = FatigueAnalysis {
        fatigue_score,
        peak_frequency,
        harmonic_density,
        temporal_density,
        recovery_factor,
        risk_level,
    };

    (analysis, fatigue)
}

/// Domain 9: Session Drift Analysis
fn analyze_session_drift(outputs: &[DeterministicParameterMap]) -> DomainAnalysis {
    if outputs.len() < 20 {
        return DomainAnalysis {
            domain: AilDomain::SessionDrift,
            score: 100.0,
            risk: 0.0,
            details: "Insufficient data".into(),
        };
    }

    let quarter = outputs.len() / 4;
    let q1_avg = outputs[..quarter]
        .iter()
        .map(|o| o.energy_density)
        .sum::<f64>()
        / quarter as f64;
    let q4_avg = outputs[3 * quarter..]
        .iter()
        .map(|o| o.energy_density)
        .sum::<f64>()
        / quarter as f64;

    let drift = q4_avg - q1_avg;

    let esc_values: Vec<f64> = outputs.iter().map(|o| o.escalation_multiplier).collect();
    let esc_mean = esc_values.iter().sum::<f64>() / esc_values.len() as f64;
    let esc_variance = esc_values
        .iter()
        .map(|e| (e - esc_mean).powi(2))
        .sum::<f64>()
        / esc_values.len() as f64;

    let energy_creep = drift > 0.15;
    let emotional_flatness = esc_variance < 0.5;

    let risk: f64 = if energy_creep && emotional_flatness {
        0.6
    } else if energy_creep {
        0.4
    } else if emotional_flatness {
        0.3
    } else {
        0.1
    };

    let score = ((1.0 - risk) * 100.0_f64).clamp(0.0, 100.0);

    DomainAnalysis {
        domain: AilDomain::SessionDrift,
        score,
        risk,
        details: format!(
            "drift={:.4} q1={:.3} q4={:.3} esc_var={:.3} creep={} flat={}",
            drift, q1_avg, q4_avg, esc_variance, energy_creep, emotional_flatness
        ),
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP GENERATOR
// ═════════════════════════════════════════════════════════════════════════════

/// Generate a mixed analysis scenario with realistic slot patterns.
fn gen_analysis_steps(count: usize) -> Vec<SimulationStep> {
    let mut steps = Vec::with_capacity(count);
    let mut seed = 42u64;

    for _ in 0..count {
        seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let r = ((seed >> 33) as f64) / (u32::MAX as f64);

        let (win_multiplier, rms_db, hf_db, volatility, jackpot_proximity) = if r < 0.05 {
            // Jackpot: 5%
            (100.0 + r * 500.0, -6.0, -12.0, 0.9, 0.95)
        } else if r < 0.15 {
            // Feature/big win: 10%
            (15.0 + r * 30.0, -10.0, -16.0, 0.7, 0.3)
        } else if r < 0.30 {
            // Cascade/medium win: 15%
            (5.0 + r * 10.0, -14.0, -20.0, 0.6, 0.1)
        } else if r < 0.50 {
            // Small win: 20%
            (1.0 + r * 4.0, -18.0, -24.0, 0.5, 0.0)
        } else {
            // No win: 50%
            (0.0, -24.0, -30.0, 0.5, 0.0)
        };

        steps.push(SimulationStep {
            elapsed_ms: 50,
            volatility,
            rtp: 96.0,
            win_multiplier,
            jackpot_proximity,
            rms_db,
            hf_db,
        });
    }

    steps
}

// ═════════════════════════════════════════════════════════════════════════════
// JSON SERIALIZATION
// ═════════════════════════════════════════════════════════════════════════════

fn report_to_json(report: &AilReport) -> Result<String, String> {
    use std::fmt::Write;

    let mut json = String::with_capacity(4096);
    write!(json, "{{").map_err(|e| e.to_string())?;

    write!(json, "\"report_version\":\"1.0\",").map_err(|e| e.to_string())?;

    // Summary
    write!(json, "\"summary\":{{").map_err(|e| e.to_string())?;
    write!(json, "\"ail_score\":{:.1},", report.score.value).map_err(|e| e.to_string())?;
    write!(
        json,
        "\"overall_status\":\"{}\",",
        report.score.status.name()
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"recommendation_count\":{},",
        report.recommendations.len()
    )
    .map_err(|e| e.to_string())?;
    write!(json, "\"critical_count\":{},", report.critical_count).map_err(|e| e.to_string())?;
    write!(json, "\"warning_count\":{},", report.warning_count).map_err(|e| e.to_string())?;
    write!(json, "\"info_count\":{},", report.info_count).map_err(|e| e.to_string())?;
    write!(json, "\"simulation_spins\":{},", report.simulation_spins).map_err(|e| e.to_string())?;
    write!(json, "\"pbse_passed\":{}", report.pbse_passed).map_err(|e| e.to_string())?;
    write!(json, "}},").map_err(|e| e.to_string())?;

    // Domain analyses
    write!(json, "\"domain_analyses\":[").map_err(|e| e.to_string())?;
    for (i, da) in report.domain_analyses.iter().enumerate() {
        if i > 0 {
            write!(json, ",").map_err(|e| e.to_string())?;
        }
        write!(
            json,
            "{{\"domain\":\"{}\",\"score\":{:.1},\"risk\":{:.4},\"details\":\"{}\"}}",
            da.domain.name(),
            da.score,
            da.risk,
            da.details.replace('\"', "\\\"")
        )
        .map_err(|e| e.to_string())?;
    }
    write!(json, "],").map_err(|e| e.to_string())?;

    // Fatigue
    write!(json, "\"fatigue_analysis\":{{").map_err(|e| e.to_string())?;
    write!(
        json,
        "\"fatigue_score\":{:.2},",
        report.fatigue.fatigue_score
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"peak_frequency\":{:.4},",
        report.fatigue.peak_frequency
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"harmonic_density\":{:.4},",
        report.fatigue.harmonic_density
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"temporal_density\":{:.4},",
        report.fatigue.temporal_density
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"recovery_factor\":{:.4},",
        report.fatigue.recovery_factor
    )
    .map_err(|e| e.to_string())?;
    write!(json, "\"risk_level\":\"{}\"", report.fatigue.risk_level).map_err(|e| e.to_string())?;
    write!(json, "}},").map_err(|e| e.to_string())?;

    // Voice efficiency
    write!(json, "\"voice_efficiency\":{{").map_err(|e| e.to_string())?;
    write!(
        json,
        "\"avg_voices\":{:.1},",
        report.voice_efficiency.avg_voices
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"peak_voices\":{},",
        report.voice_efficiency.peak_voices
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"budget_cap\":{},",
        report.voice_efficiency.budget_cap
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"utilization_pct\":{:.1},",
        report.voice_efficiency.utilization_pct
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"efficiency_score\":{:.1}",
        report.voice_efficiency.efficiency_score
    )
    .map_err(|e| e.to_string())?;
    write!(json, "}},").map_err(|e| e.to_string())?;

    // Spectral clarity
    write!(json, "\"spectral_clarity\":{{").map_err(|e| e.to_string())?;
    write!(
        json,
        "\"sci_advanced\":{:.4},",
        report.spectral_clarity.sci_advanced
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"sci_limit\":{:.2},",
        report.spectral_clarity.sci_limit
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"clarity_score\":{:.1},",
        report.spectral_clarity.clarity_score
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"overlap_count\":{}",
        report.spectral_clarity.overlap_count
    )
    .map_err(|e| e.to_string())?;
    write!(json, "}},").map_err(|e| e.to_string())?;

    // Volatility alignment
    write!(json, "\"volatility_alignment\":{{").map_err(|e| e.to_string())?;
    write!(
        json,
        "\"alignment_score\":{:.1},",
        report.volatility_alignment.alignment_score
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"energy_variance\":{:.4},",
        report.volatility_alignment.energy_variance
    )
    .map_err(|e| e.to_string())?;
    write!(
        json,
        "\"escalation_range\":{:.2}",
        report.volatility_alignment.escalation_range
    )
    .map_err(|e| e.to_string())?;
    write!(json, "}},").map_err(|e| e.to_string())?;

    // Ranked recommendations
    write!(json, "\"ranked_recommendations\":[").map_err(|e| e.to_string())?;
    for (i, rec) in report.recommendations.iter().enumerate() {
        if i > 0 {
            write!(json, ",").map_err(|e| e.to_string())?;
        }
        write!(json, "{{\"rank\":{},\"level\":\"{}\",\"domain\":\"{}\",\"title\":\"{}\",\"description\":\"{}\",\"impact_score\":{:.1},\"effort\":\"{}\"}}",
            rec.rank, rec.level.name(), rec.domain.name(),
            rec.title.replace('\"', "\\\""),
            rec.description.replace('\"', "\\\""),
            rec.impact_score, rec.effort.name()).map_err(|e| e.to_string())?;
    }
    write!(json, "]").map_err(|e| e.to_string())?;

    write!(json, "}}").map_err(|e| e.to_string())?;
    Ok(json)
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ail_domain_count() {
        assert_eq!(AilDomain::COUNT, 10);
        assert_eq!(AilDomain::all().len(), 10);
    }

    #[test]
    fn test_ail_domain_from_index() {
        for i in 0..10u8 {
            assert!(AilDomain::from_index(i).is_some());
        }
        assert!(AilDomain::from_index(10).is_none());
    }

    #[test]
    fn test_ail_domain_names() {
        assert_eq!(AilDomain::HookFrequency.name(), "Hook Frequency");
        assert_eq!(AilDomain::SessionDrift.name(), "Session Drift");
    }

    #[test]
    fn test_ail_status_from_score() {
        assert_eq!(AilStatus::from_score(95.0), AilStatus::Excellent);
        assert_eq!(AilStatus::from_score(80.0), AilStatus::Good);
        assert_eq!(AilStatus::from_score(65.0), AilStatus::Fair);
        assert_eq!(AilStatus::from_score(45.0), AilStatus::Poor);
        assert_eq!(AilStatus::from_score(20.0), AilStatus::Critical);
    }

    #[test]
    fn test_recommendation_level_ordering() {
        assert!(RecommendationLevel::Info < RecommendationLevel::Warning);
        assert!(RecommendationLevel::Warning < RecommendationLevel::Critical);
    }

    #[test]
    fn test_analyze_full() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        assert!(report.score.value >= 0.0 && report.score.value <= 100.0);
        assert_eq!(report.domain_analyses.len(), 10);
        assert_eq!(report.simulation_spins, 500);
        assert!(!report.pbse_passed);

        for da in &report.domain_analyses {
            assert!(
                da.score >= 0.0 && da.score <= 100.0,
                "Domain {:?} score={}",
                da.domain,
                da.score
            );
            assert!(
                da.risk >= 0.0 && da.risk <= 1.0,
                "Domain {:?} risk={}",
                da.domain,
                da.risk
            );
        }
    }

    #[test]
    fn test_ail_score_formula() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        let avg_risk: f64 = report.domain_analyses.iter().map(|d| d.risk).sum::<f64>() / 10.0;
        let expected = (100.0 * (1.0 - avg_risk)).clamp(0.0, 100.0);
        assert!(
            (report.score.value - expected).abs() < 0.01,
            "Expected score={:.2}, got={:.2}",
            expected,
            report.score.value
        );
    }

    #[test]
    fn test_recommendations_sorted_by_impact() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        for i in 1..report.recommendations.len() {
            assert!(
                report.recommendations[i - 1].impact_score
                    >= report.recommendations[i].impact_score,
                "Recommendations not sorted by impact at index {}",
                i
            );
        }
    }

    #[test]
    fn test_recommendations_ranked() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        for (i, rec) in report.recommendations.iter().enumerate() {
            assert_eq!(rec.rank, (i + 1) as u32);
        }
    }

    #[test]
    fn test_json_output() {
        let mut ail = AuthoringIntelligence::new();
        ail.analyze(None);

        let json = ail.report_json().expect("JSON generation failed");
        assert!(json.contains("\"report_version\":\"1.0\""));
        assert!(json.contains("\"ail_score\":"));
        assert!(json.contains("\"overall_status\":"));
        assert!(json.contains("\"domain_analyses\":["));
        assert!(json.contains("\"fatigue_analysis\":{"));
        assert!(json.contains("\"voice_efficiency\":{"));
        assert!(json.contains("\"spectral_clarity\":{"));
        assert!(json.contains("\"ranked_recommendations\":["));
    }

    #[test]
    fn test_last_report() {
        let mut ail = AuthoringIntelligence::new();
        assert!(ail.last_report().is_none());

        ail.analyze(None);
        assert!(ail.last_report().is_some());

        ail.reset();
        assert!(ail.last_report().is_none());
    }

    #[test]
    fn test_with_pbse_result() {
        let pbse_result = PbseResult {
            domains: (0..10)
                .map(|i| crate::qa::pbse::DomainResult {
                    domain: crate::qa::pbse::SimulationDomain::from_index(i).unwrap(),
                    passed: true,
                    spin_count: 100,
                    peak_energy_cap: 0.8,
                    peak_voice_count: 20,
                    peak_sci: 0.5,
                    peak_fatigue: 0.3,
                    peak_escalation: 1.0,
                    escalation_slope: 1.0,
                    deterministic: true,
                    metrics: vec![],
                })
                .collect(),
            all_passed: true,
            bake_unlocked: true,
            fatigue_model: crate::qa::pbse::FatigueModelResult {
                fatigue_index: 0.3,
                peak_frequency: 0.2,
                harmonic_density: 0.5,
                temporal_density: 0.3,
                recovery_factor: 0.1,
                passed: true,
                threshold: 0.9,
            },
            determinism_verified: true,
            total_spins: 1000,
        };

        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(Some(&pbse_result));
        assert!(report.pbse_passed);
    }

    #[test]
    fn test_gen_analysis_steps() {
        let steps = gen_analysis_steps(500);
        assert_eq!(steps.len(), 500);

        let high_wins = steps.iter().filter(|s| s.win_multiplier > 10.0).count();
        let low_wins = steps
            .iter()
            .filter(|s| s.win_multiplier > 0.0 && s.win_multiplier <= 10.0)
            .count();
        let jackpots = steps.iter().filter(|s| s.jackpot_proximity > 0.5).count();

        // With PCG/LCG generator, distribution should include various categories
        assert!(high_wins + low_wins > 0, "Should have some wins");
        assert!(
            jackpots > 0 || high_wins > 0,
            "Should have high-intensity events"
        );

        // All steps should have valid fields
        for step in &steps {
            assert_eq!(step.elapsed_ms, 50);
            assert!(step.volatility >= 0.0 && step.volatility <= 1.0);
            assert!(step.rtp > 0.0);
        }
    }

    #[test]
    fn test_fatigue_analysis_components() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        assert!(report.fatigue.peak_frequency >= 0.0 && report.fatigue.peak_frequency <= 1.0);
        assert!(report.fatigue.harmonic_density >= 0.0);
        assert!(report.fatigue.temporal_density >= 0.0);
        assert!(report.fatigue.recovery_factor > 0.0);
        assert!(["LOW", "MODERATE", "HIGH", "CRITICAL"].contains(&report.fatigue.risk_level));
    }

    #[test]
    fn test_voice_efficiency_bounds() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        assert_eq!(report.voice_efficiency.budget_cap, 48);
        assert!(report.voice_efficiency.utilization_pct >= 0.0);
        assert!(
            report.voice_efficiency.efficiency_score >= 0.0
                && report.voice_efficiency.efficiency_score <= 100.0
        );
    }

    #[test]
    fn test_spectral_clarity_bounds() {
        let mut ail = AuthoringIntelligence::new();
        let report = ail.analyze(None);

        assert_eq!(report.spectral_clarity.sci_limit, 0.85);
        assert!(
            report.spectral_clarity.clarity_score >= 0.0
                && report.spectral_clarity.clarity_score <= 100.0
        );
    }
}
