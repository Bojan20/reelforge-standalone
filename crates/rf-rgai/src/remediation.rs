//! Auto-remediation — suggests parameter changes to bring assets into compliance.

use crate::analysis::AssetAnalysis;
use crate::jurisdiction::JurisdictionProfile;
use crate::metrics::MetricViolation;
use serde::{Deserialize, Serialize};

/// A suggested remediation action for a single metric violation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationAction {
    /// Which metric is violated.
    pub metric: String,
    /// What to change.
    pub suggestion: String,
    /// How much to reduce the metric by.
    pub target_reduction: f64,
    /// Specific parameter adjustments.
    pub adjustments: Vec<ParameterAdjustment>,
    /// Estimated impact on player experience (0=none, 1=severe).
    pub experience_impact: f64,
}

/// A specific parameter change to bring a metric into compliance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParameterAdjustment {
    pub parameter: String,
    pub current_contribution: f64,
    pub suggested_value: f64,
    pub rationale: String,
}

/// Complete remediation plan for an asset.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationPlan {
    pub asset_id: String,
    pub actions: Vec<RemediationAction>,
    /// Estimated post-remediation risk rating.
    pub projected_risk: String,
}

impl RemediationPlan {
    /// Generate a remediation plan for a failing asset.
    pub fn generate(analysis: &AssetAnalysis, profile: &JurisdictionProfile) -> Option<Self> {
        let violations = analysis.metrics.violations(profile);
        if violations.is_empty() {
            return None;
        }

        let actions: Vec<RemediationAction> = violations
            .iter()
            .map(Self::remediate_violation)
            .collect();

        Some(Self {
            asset_id: analysis.asset_id.clone(),
            actions,
            projected_risk: "MEDIUM".to_string(), // conservative estimate
        })
    }

    fn remediate_violation(v: &MetricViolation) -> RemediationAction {
        match v.metric.as_str() {
            "arousal" => RemediationAction {
                metric: "arousal".to_string(),
                suggestion: "Reduce audio energy density and escalation rate".to_string(),
                target_reduction: v.excess + 0.05, // 5% safety margin
                adjustments: vec![
                    ParameterAdjustment {
                        parameter: "energy_density".to_string(),
                        current_contribution: v.actual * 0.30,
                        suggested_value: (v.threshold - 0.05).max(0.0) / 0.30,
                        rationale: "Reduce broadband energy — use narrower frequency bands"
                            .to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "escalation_rate".to_string(),
                        current_contribution: v.actual * 0.20,
                        suggested_value: (v.threshold - 0.05).max(0.0) / 0.20,
                        rationale: "Flatten the intensity curve — avoid sharp ramps".to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "celebration_delta".to_string(),
                        current_contribution: v.actual * 0.15,
                        suggested_value: (v.threshold - 0.05).max(0.0) / 0.15,
                        rationale:
                            "Reduce loudness gap between win and ambient — bring closer together"
                                .to_string(),
                    },
                ],
                experience_impact: 0.3,
            },
            "near_miss_deception" => RemediationAction {
                metric: "near_miss_deception".to_string(),
                suggestion: "Make near-miss audio clearly distinct from win audio".to_string(),
                target_reduction: v.excess + 0.05,
                adjustments: vec![
                    ParameterAdjustment {
                        parameter: "spectral_similarity_to_win".to_string(),
                        current_contribution: v.actual * 0.40,
                        suggested_value: 0.2,
                        rationale: "Use different timbre/instruments for near-miss vs win"
                            .to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "anticipation_buildup".to_string(),
                        current_contribution: v.actual * 0.30,
                        suggested_value: 0.2,
                        rationale: "Reduce tension ramp — keep it neutral, not exciting"
                            .to_string(),
                    },
                ],
                experience_impact: 0.2,
            },
            "loss_disguise" => RemediationAction {
                metric: "loss_disguise".to_string(),
                suggestion: "Ensure loss sounds are clearly distinct from win sounds (LDW compliance)".to_string(),
                target_reduction: v.excess + 0.05,
                adjustments: vec![
                    ParameterAdjustment {
                        parameter: "spectral_similarity_loss_win".to_string(),
                        current_contribution: v.actual * 0.50,
                        suggested_value: 0.15,
                        rationale: "Use completely different sound palette for losses — no shared elements with wins".to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "celebratory_elements".to_string(),
                        current_contribution: v.actual * 0.25,
                        suggested_value: 0.0,
                        rationale: "Remove ALL celebratory elements (fanfare, chimes, jingles) from loss sounds".to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "positive_tonality".to_string(),
                        current_contribution: v.actual * 0.25,
                        suggested_value: 0.1,
                        rationale: "Use neutral or minor key for loss sounds — avoid bright/major tonality".to_string(),
                    },
                ],
                experience_impact: 0.15,
            },
            "temporal_distortion" => RemediationAction {
                metric: "temporal_distortion".to_string(),
                suggestion: "Introduce natural pauses and tempo variation".to_string(),
                target_reduction: v.excess + 0.05,
                adjustments: vec![
                    ParameterAdjustment {
                        parameter: "silence_absence".to_string(),
                        current_contribution: v.actual * 0.25,
                        suggested_value: 0.4,
                        rationale: "Add natural silences between events — let the player breathe"
                            .to_string(),
                    },
                    ParameterAdjustment {
                        parameter: "tempo_stability".to_string(),
                        current_contribution: v.actual * 0.25,
                        suggested_value: 0.4,
                        rationale: "Introduce BPM variation — monotonous tempo induces dissociative flow".to_string(),
                    },
                ],
                experience_impact: 0.2,
            },
            _ => RemediationAction {
                metric: v.metric.to_string(),
                suggestion: format!("Reduce {} by {:.2}", v.metric, v.excess),
                target_reduction: v.excess + 0.05,
                adjustments: vec![],
                experience_impact: 0.1,
            },
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analysis::RgaiAnalyzer;
    use crate::jurisdiction::Jurisdiction;
    use crate::session::AudioAssetProfile;

    #[test]
    fn no_plan_for_clean_asset() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let asset = AudioAssetProfile::safe_default("clean", "ambient");
        let analysis = analyzer.analyze_asset(&asset);
        let profile = Jurisdiction::Ukgc.profile();
        let plan = RemediationPlan::generate(&analysis, &profile);
        assert!(plan.is_none());
    }

    #[test]
    fn plan_generated_for_arousal_violation() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut asset = AudioAssetProfile::safe_default("hot", "win_celebration");
        asset.energy_density = 0.95;
        asset.escalation_rate = 0.9;
        asset.normalized_bpm = 0.8;
        asset.celebration_delta = 0.85;
        asset.dynamic_range = 0.7;
        let analysis = analyzer.analyze_asset(&asset);
        let profile = Jurisdiction::Ukgc.profile();
        let plan = RemediationPlan::generate(&analysis, &profile);
        assert!(plan.is_some());
        let plan = plan.unwrap();
        assert!(!plan.actions.is_empty());
        assert!(plan
            .actions
            .iter()
            .any(|a| a.metric == "arousal"));
    }

    #[test]
    fn plan_generated_for_loss_disguise_violation() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut asset = AudioAssetProfile::safe_default("ldw_bad", "loss");
        asset.spectral_similarity_loss_win = 0.8;
        asset.positive_tonality = 0.7;
        asset.celebratory_elements = 0.6;
        let analysis = analyzer.analyze_asset(&asset);
        let profile = Jurisdiction::Ukgc.profile();
        let plan = RemediationPlan::generate(&analysis, &profile);
        assert!(plan.is_some());
        let plan = plan.unwrap();
        assert!(plan.actions.iter().any(|a| a.metric == "loss_disguise"));
        // Should suggest removing celebratory elements
        let ldw_action = plan.actions.iter().find(|a| a.metric == "loss_disguise").unwrap();
        assert!(ldw_action.adjustments.iter().any(|adj| adj.parameter == "celebratory_elements" && adj.suggested_value == 0.0));
    }

    #[test]
    fn remediation_has_safety_margin() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut asset = AudioAssetProfile::safe_default("margin_test", "ambient");
        asset.energy_density = 0.9;
        asset.escalation_rate = 0.8;
        let analysis = analyzer.analyze_asset(&asset);
        let profile = Jurisdiction::Ukgc.profile();
        let plan = RemediationPlan::generate(&analysis, &profile);
        if let Some(plan) = plan {
            for action in &plan.actions {
                // target_reduction should be excess + 0.05 safety margin
                assert!(action.target_reduction > 0.05);
            }
        }
    }

    #[test]
    fn experience_impact_reasonable() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut asset = AudioAssetProfile::safe_default("exp", "near_miss");
        asset.spectral_similarity_to_win = 0.9;
        asset.anticipation_buildup = 0.8;
        let analysis = analyzer.analyze_asset(&asset);
        let profile = Jurisdiction::Ukgc.profile();
        let plan = RemediationPlan::generate(&analysis, &profile);
        if let Some(plan) = plan {
            for action in &plan.actions {
                assert!(action.experience_impact >= 0.0 && action.experience_impact <= 1.0);
            }
        }
    }
}
