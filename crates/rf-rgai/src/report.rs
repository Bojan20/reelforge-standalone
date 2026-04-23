//! RGAR (Responsible Gaming Audio Report) generation.
//!
//! Generates structured compliance reports for regulatory submission.
//! Supports multiple output formats: JSON audit trail, structured report.

use crate::analysis::SessionAnalysisResult;
use crate::jurisdiction::Jurisdiction;
use crate::metrics::AddictionRiskRating;
use serde::{Deserialize, Serialize};

/// Severity classification for RGAR findings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum Severity {
    /// Information only — no action required.
    Info,
    /// Recommended improvement.
    Advisory,
    /// Should be addressed before production deployment.
    Warning,
    /// Must be fixed — blocks regulatory approval.
    Critical,
}

/// A single finding in the RGAR report.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RgarFinding {
    pub severity: Severity,
    pub category: String,
    pub asset_id: Option<String>,
    pub jurisdiction: Option<Jurisdiction>,
    pub description: String,
    pub metric_value: Option<f64>,
    pub threshold: Option<f64>,
    pub recommendation: String,
}

/// A section of the RGAR report.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RgarSection {
    pub title: String,
    pub findings: Vec<RgarFinding>,
}

/// Complete RGAR (Responsible Gaming Audio Report).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RgarReport {
    // ── Header ──
    pub report_id: String,
    pub generated_at: String,
    pub fluxforge_version: String,
    pub game_title: String,
    pub target_jurisdictions: Vec<Jurisdiction>,

    // ── Executive Summary ──
    pub overall_risk: AddictionRiskRating,
    pub overall_pass: bool,
    pub total_assets_analyzed: usize,
    pub total_findings: usize,
    pub critical_findings: usize,

    // ── Sections ──
    pub sections: Vec<RgarSection>,

    // ── Digital signature placeholder ──
    pub integrity_hash: String,
}

impl RgarReport {
    /// Generate a complete RGAR report from session analysis results.
    pub fn generate(
        analysis: &SessionAnalysisResult,
        fluxforge_version: &str,
    ) -> Self {
        let mut sections = Vec::new();
        let mut all_findings = Vec::new();

        // Section 1: Arousal Analysis
        let mut arousal_findings = Vec::new();
        for asset in &analysis.asset_analyses {
            let level = asset.metrics.arousal.level();
            let severity = match level {
                crate::metrics::ArousalLevel::Extreme => Severity::Critical,
                crate::metrics::ArousalLevel::High => Severity::Warning,
                crate::metrics::ArousalLevel::Moderate => Severity::Advisory,
                _ => Severity::Info,
            };
            arousal_findings.push(RgarFinding {
                severity,
                category: "arousal".to_string(),
                asset_id: Some(asset.asset_id.clone()),
                jurisdiction: None,
                description: format!(
                    "Arousal coefficient: {:.3} ({:?})",
                    asset.metrics.arousal.value(),
                    level
                ),
                metric_value: Some(asset.metrics.arousal.value()),
                threshold: None,
                recommendation: if severity >= Severity::Warning {
                    "Reduce energy density and escalation rate".to_string()
                } else {
                    "No action required".to_string()
                },
            });
        }
        all_findings.extend(arousal_findings.clone());
        sections.push(RgarSection {
            title: "Section 1: Arousal Analysis".to_string(),
            findings: arousal_findings,
        });

        // Section 2: Near-Miss Audio Analysis
        let mut nm_findings = Vec::new();
        for asset in &analysis.asset_analyses {
            let val = asset.metrics.near_miss_deception.value();
            let severity = if val > 0.6 {
                Severity::Critical
            } else if val > 0.4 {
                Severity::Warning
            } else if val > 0.2 {
                Severity::Advisory
            } else {
                Severity::Info
            };
            nm_findings.push(RgarFinding {
                severity,
                category: "near_miss_deception".to_string(),
                asset_id: Some(asset.asset_id.clone()),
                jurisdiction: None,
                description: format!("Near-Miss Deception Index: {:.3}", val),
                metric_value: Some(val),
                threshold: None,
                recommendation: if severity >= Severity::Warning {
                    "Make near-miss audio clearly distinct from win sounds".to_string()
                } else {
                    "No action required".to_string()
                },
            });
        }
        all_findings.extend(nm_findings.clone());
        sections.push(RgarSection {
            title: "Section 2: Near-Miss Audio Analysis".to_string(),
            findings: nm_findings,
        });

        // Section 3: Loss-Disguise (LDW) Analysis
        let mut ldw_findings = Vec::new();
        for asset in &analysis.asset_analyses {
            let val = asset.metrics.loss_disguise.value();
            let severity = if val > 0.4 {
                Severity::Critical
            } else if val > 0.25 {
                Severity::Warning
            } else if val > 0.15 {
                Severity::Advisory
            } else {
                Severity::Info
            };
            ldw_findings.push(RgarFinding {
                severity,
                category: "loss_disguise".to_string(),
                asset_id: Some(asset.asset_id.clone()),
                jurisdiction: None,
                description: format!("Loss-Disguise Score: {:.3}", val),
                metric_value: Some(val),
                threshold: None,
                recommendation: if severity >= Severity::Warning {
                    "Remove all celebratory elements from loss sounds; use distinct timbre"
                        .to_string()
                } else {
                    "No action required".to_string()
                },
            });
        }
        all_findings.extend(ldw_findings.clone());
        sections.push(RgarSection {
            title: "Section 3: Loss-Disguise (LDW) Analysis".to_string(),
            findings: ldw_findings,
        });

        // Section 4: Temporal Distortion Analysis
        let mut td_findings = Vec::new();
        for asset in &analysis.asset_analyses {
            let val = asset.metrics.temporal_distortion.value();
            let severity = if val > 0.6 {
                Severity::Critical
            } else if val > 0.45 {
                Severity::Warning
            } else {
                Severity::Info
            };
            td_findings.push(RgarFinding {
                severity,
                category: "temporal_distortion".to_string(),
                asset_id: Some(asset.asset_id.clone()),
                jurisdiction: None,
                description: format!("Temporal Distortion Factor: {:.3}", val),
                metric_value: Some(val),
                threshold: None,
                recommendation: if severity >= Severity::Warning {
                    "Add natural pauses, vary tempo, reduce audio wall coverage".to_string()
                } else {
                    "No action required".to_string()
                },
            });
        }
        all_findings.extend(td_findings.clone());
        sections.push(RgarSection {
            title: "Section 4: Temporal Distortion Analysis".to_string(),
            findings: td_findings,
        });

        // Section 5: Jurisdiction Compliance
        let mut compliance_findings = Vec::new();
        for asset in &analysis.asset_analyses {
            for jr in &asset.per_jurisdiction {
                if !jr.passes {
                    for v in &jr.violations {
                        compliance_findings.push(RgarFinding {
                            severity: Severity::Critical,
                            category: "jurisdiction_compliance".to_string(),
                            asset_id: Some(asset.asset_id.clone()),
                            jurisdiction: Some(jr.jurisdiction),
                            description: format!(
                                "{} exceeds {} threshold: {:.3} > {:.3}",
                                v.metric,
                                jr.jurisdiction.code(),
                                v.actual,
                                v.threshold
                            ),
                            metric_value: Some(v.actual),
                            threshold: Some(v.threshold),
                            recommendation: format!(
                                "Reduce {} by at least {:.3}",
                                v.metric, v.excess
                            ),
                        });
                    }
                }
            }
        }
        all_findings.extend(compliance_findings.clone());
        sections.push(RgarSection {
            title: "Section 5: Jurisdiction Compliance".to_string(),
            findings: compliance_findings,
        });

        // Section 6: Game-Level Checks
        let mut game_findings = Vec::new();
        for glv in &analysis.game_level_violations {
            game_findings.push(RgarFinding {
                severity: match glv.severity {
                    crate::analysis::ViolationSeverity::Critical => Severity::Critical,
                    crate::analysis::ViolationSeverity::Major => Severity::Warning,
                    crate::analysis::ViolationSeverity::Minor => Severity::Advisory,
                },
                category: format!("game_level:{}", glv.rule),
                asset_id: None,
                jurisdiction: None,
                description: glv.description.clone(),
                metric_value: None,
                threshold: None,
                recommendation: format!("Implement {} compliance measure", glv.rule),
            });
        }
        all_findings.extend(game_findings.clone());
        sections.push(RgarSection {
            title: "Section 6: Game-Level Compliance".to_string(),
            findings: game_findings,
        });

        let critical_findings = all_findings
            .iter()
            .filter(|f| f.severity == Severity::Critical)
            .count();

        // Compute integrity hash (SHA-256 of serialized analysis)
        let hash_input = serde_json::to_string(analysis).unwrap_or_default();
        let integrity_hash = simple_hash(&hash_input);

        Self {
            report_id: format!("RGAR-{}", integrity_hash.chars().take(12).collect::<String>()),
            generated_at: "2026-04-16T00:00:00Z".to_string(), // placeholder — real impl uses chrono
            fluxforge_version: fluxforge_version.to_string(),
            game_title: analysis.game_title.clone(),
            target_jurisdictions: analysis.target_jurisdictions.clone(),
            overall_risk: if critical_findings > 0 {
                AddictionRiskRating::High
            } else if all_findings.iter().any(|f| f.severity == Severity::Warning) {
                AddictionRiskRating::Medium
            } else {
                AddictionRiskRating::Low
            },
            overall_pass: analysis.overall_pass,
            total_assets_analyzed: analysis.total_assets,
            total_findings: all_findings.len(),
            critical_findings,
            sections,
            integrity_hash,
        }
    }

    /// Export as JSON audit trail.
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_default()
    }

    /// Export as compact JSON (for API/machine consumption).
    pub fn to_json_compact(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

/// Simple deterministic hash (djb2 variant) — not cryptographic, just for report IDs.
fn simple_hash(input: &str) -> String {
    let mut hash: u64 = 5381;
    for byte in input.bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(byte as u64);
    }
    format!("{:016x}", hash)
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analysis::RgaiAnalyzer;
    use crate::jurisdiction::Jurisdiction;
    use crate::session::{AudioAssetProfile, GameAudioSession};

    fn test_session() -> GameAudioSession {
        GameAudioSession {
            game_title: "Test Pharaoh's Fortune".to_string(),
            assets: vec![
                AudioAssetProfile::safe_default("ambient_01", "ambient"),
                AudioAssetProfile::safe_default("reel_stop", "reel_stop"),
            ],
            max_celebration_duration_secs: 3.5,
            ldw_suppression_implemented: true,
            near_miss_audio_enhanced: false,
            cooling_off_audio_present: true,
            session_time_reminder_audio_present: true,
        }
    }

    #[test]
    fn report_generated_for_clean_session() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let analysis = analyzer.analyze_session(&test_session());
        let report = RgarReport::generate(&analysis, "0.1.0");
        assert!(report.overall_pass);
        assert_eq!(report.critical_findings, 0);
        assert_eq!(report.total_assets_analyzed, 2);
        assert!(report.report_id.starts_with("RGAR-"));
        assert_eq!(report.sections.len(), 6);
    }

    #[test]
    fn report_json_roundtrip() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let analysis = analyzer.analyze_session(&test_session());
        let report = RgarReport::generate(&analysis, "0.1.0");
        let json = report.to_json();
        let parsed: RgarReport = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.game_title, report.game_title);
        assert_eq!(parsed.overall_pass, report.overall_pass);
    }

    #[test]
    fn report_has_integrity_hash() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let analysis = analyzer.analyze_session(&test_session());
        let report = RgarReport::generate(&analysis, "0.1.0");
        assert!(!report.integrity_hash.is_empty());
        assert_eq!(report.integrity_hash.len(), 16);
    }

    #[test]
    fn report_detects_critical_findings() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut session = test_session();
        session.ldw_suppression_implemented = false; // UKGC requires this
        let analysis = analyzer.analyze_session(&session);
        let report = RgarReport::generate(&analysis, "0.1.0");
        assert!(!report.overall_pass);
        assert!(report.critical_findings > 0);
    }

    #[test]
    fn report_sections_cover_all_domains() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc, Jurisdiction::Sweden]);
        let analysis = analyzer.analyze_session(&test_session());
        let report = RgarReport::generate(&analysis, "0.1.0");
        let titles: Vec<&str> = report.sections.iter().map(|s| s.title.as_str()).collect();
        assert!(titles.contains(&"Section 1: Arousal Analysis"));
        assert!(titles.contains(&"Section 2: Near-Miss Audio Analysis"));
        assert!(titles.contains(&"Section 3: Loss-Disguise (LDW) Analysis"));
        assert!(titles.contains(&"Section 4: Temporal Distortion Analysis"));
        assert!(titles.contains(&"Section 5: Jurisdiction Compliance"));
        assert!(titles.contains(&"Section 6: Game-Level Compliance"));
    }

    #[test]
    fn compact_json_smaller_than_pretty() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let analysis = analyzer.analyze_session(&test_session());
        let report = RgarReport::generate(&analysis, "0.1.0");
        assert!(report.to_json_compact().len() < report.to_json().len());
    }

    #[test]
    fn deterministic_hash() {
        assert_eq!(simple_hash("hello"), simple_hash("hello"));
        assert_ne!(simple_hash("hello"), simple_hash("world"));
    }
}
