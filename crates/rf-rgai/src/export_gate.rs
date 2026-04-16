//! Export Gate — blocks export if compliance fails.
//!
//! This is the hard enforcement point: no manual override.
//! If RGAI metrics exceed jurisdiction thresholds, the export
//! physically cannot proceed.

use crate::analysis::{RgaiAnalyzer, SessionAnalysisResult, ViolationSeverity};
use crate::jurisdiction::Jurisdiction;
use crate::session::GameAudioSession;
use serde::{Deserialize, Serialize};

/// Export gate decision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExportDecision {
    /// All clear — export may proceed.
    Approved,
    /// Export blocked — compliance violations exist.
    Blocked {
        /// Number of critical violations.
        critical_count: usize,
        /// Number of major violations.
        major_count: usize,
        /// Human-readable summary of why export is blocked.
        reasons: Vec<String>,
    },
}

impl ExportDecision {
    pub fn is_approved(&self) -> bool {
        matches!(self, Self::Approved)
    }
}

/// The export gate — evaluates whether a game can be exported.
#[derive(Debug, Clone)]
pub struct ExportGate {
    analyzer: RgaiAnalyzer,
}

impl ExportGate {
    pub fn new(jurisdictions: Vec<Jurisdiction>) -> Self {
        Self {
            analyzer: RgaiAnalyzer::new(jurisdictions),
        }
    }

    /// Check if export is allowed. Returns Approved or Blocked with reasons.
    pub fn evaluate(&self, session: &GameAudioSession) -> ExportGateResult {
        let analysis = self.analyzer.analyze_session(session);

        let mut reasons = Vec::new();
        let mut critical_count = 0;
        let mut major_count = 0;

        // Check game-level violations
        for v in &analysis.game_level_violations {
            match v.severity {
                ViolationSeverity::Critical => critical_count += 1,
                ViolationSeverity::Major => major_count += 1,
                ViolationSeverity::Minor => {}
            }
            reasons.push(format!("[{}] {}", v.rule, v.description));
        }

        // Check per-asset violations
        for asset in &analysis.asset_analyses {
            for jr in &asset.per_jurisdiction {
                if !jr.passes {
                    for v in &jr.violations {
                        critical_count += 1;
                        reasons.push(format!(
                            "Asset '{}': {} = {:.2} exceeds {} limit {:.2} (excess: {:.2})",
                            asset.asset_id,
                            v.metric,
                            v.actual,
                            jr.jurisdiction.code(),
                            v.threshold,
                            v.excess,
                        ));
                    }
                }
            }
        }

        let decision = if critical_count == 0 && major_count == 0 {
            ExportDecision::Approved
        } else {
            ExportDecision::Blocked {
                critical_count,
                major_count,
                reasons,
            }
        };

        ExportGateResult { decision, analysis }
    }
}

/// Full export gate result — decision + detailed analysis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportGateResult {
    pub decision: ExportDecision,
    pub analysis: SessionAnalysisResult,
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{AudioAssetProfile, GameAudioSession};

    fn clean_session() -> GameAudioSession {
        GameAudioSession {
            game_title: "Clean Slot".to_string(),
            assets: vec![AudioAssetProfile::safe_default("amb", "ambient")],
            max_celebration_duration_secs: 3.0,
            ldw_suppression_implemented: true,
            near_miss_audio_enhanced: false,
            cooling_off_audio_present: true,
            session_time_reminder_audio_present: true,
        }
    }

    #[test]
    fn clean_session_approved() {
        let gate = ExportGate::new(vec![Jurisdiction::Ukgc]);
        let result = gate.evaluate(&clean_session());
        assert!(result.decision.is_approved());
    }

    #[test]
    fn dirty_session_blocked() {
        let gate = ExportGate::new(vec![Jurisdiction::Ukgc]);
        let mut session = clean_session();
        session.ldw_suppression_implemented = false;
        session.near_miss_audio_enhanced = true;
        let result = gate.evaluate(&session);
        assert!(!result.decision.is_approved());
        if let ExportDecision::Blocked {
            critical_count,
            reasons,
            ..
        } = &result.decision
        {
            assert!(*critical_count >= 2);
            assert!(reasons.iter().any(|r| r.contains("ldw_suppression")));
            assert!(reasons.iter().any(|r| r.contains("near_miss_enhancement")));
        }
    }

    #[test]
    fn risky_asset_blocks_export() {
        let gate = ExportGate::new(vec![Jurisdiction::Ukgc]);
        let mut session = clean_session();
        session.assets.push(AudioAssetProfile {
            id: "win_mega".to_string(),
            category: "win_celebration".to_string(),
            energy_density: 0.95,
            escalation_rate: 0.9,
            normalized_bpm: 0.8,
            celebration_delta: 0.9,
            dynamic_range: 0.7,
            spectral_similarity_to_win: 0.1,
            anticipation_buildup: 0.1,
            resolve_disappointment: 0.1,
            reel_stop_delay: 0.1,
            spectral_similarity_loss_win: 0.1,
            positive_tonality: 0.1,
            celebratory_elements: 0.0,
            loop_seamlessness: 0.1,
            tempo_stability: 0.1,
            silence_absence: 0.1,
            duration_inflation: 0.1,
        });
        let result = gate.evaluate(&session);
        assert!(!result.decision.is_approved());
    }

    #[test]
    fn multi_jurisdiction_blocks_on_any_failure() {
        let gate = ExportGate::new(vec![
            Jurisdiction::Ukgc,
            Jurisdiction::Mga,
            Jurisdiction::Sweden,
        ]);
        let mut session = clean_session();
        // Celebration too long for Sweden (max 4s)
        session.max_celebration_duration_secs = 5.0;
        let result = gate.evaluate(&session);
        assert!(!result.decision.is_approved());
    }

    #[test]
    fn permissive_jurisdiction_approves_everything() {
        let gate = ExportGate::new(vec![Jurisdiction::Custom]);
        let session = GameAudioSession {
            game_title: "Wild Slot".to_string(),
            assets: vec![AudioAssetProfile {
                id: "crazy".to_string(),
                category: "everything".to_string(),
                energy_density: 0.99,
                escalation_rate: 0.99,
                normalized_bpm: 0.99,
                celebration_delta: 0.99,
                dynamic_range: 0.99,
                spectral_similarity_to_win: 0.99,
                anticipation_buildup: 0.99,
                resolve_disappointment: 0.99,
                reel_stop_delay: 0.99,
                spectral_similarity_loss_win: 0.99,
                positive_tonality: 0.99,
                celebratory_elements: 0.99,
                loop_seamlessness: 0.99,
                tempo_stability: 0.99,
                silence_absence: 0.99,
                duration_inflation: 0.99,
            }],
            max_celebration_duration_secs: 29.0,
            ldw_suppression_implemented: false,
            near_miss_audio_enhanced: true,
            cooling_off_audio_present: false,
            session_time_reminder_audio_present: false,
        };
        let result = gate.evaluate(&session);
        assert!(result.decision.is_approved());
    }
}
