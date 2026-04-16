//! RgaiAnalyzer — the main engine that computes RGAI metrics for audio assets.

use crate::jurisdiction::{Jurisdiction, JurisdictionProfile};
use crate::metrics::*;
use crate::session::{AudioAssetProfile, GameAudioSession};
use serde::{Deserialize, Serialize};

/// Main RGAI analysis engine.
#[derive(Debug, Clone)]
pub struct RgaiAnalyzer {
    /// Target jurisdictions — metrics are checked against ALL of these.
    jurisdictions: Vec<Jurisdiction>,
    /// Merged profile (strictest thresholds across all targets).
    merged_profile: JurisdictionProfile,
}

impl RgaiAnalyzer {
    /// Create an analyzer targeting one or more jurisdictions.
    pub fn new(jurisdictions: Vec<Jurisdiction>) -> Self {
        let merged_profile = JurisdictionProfile::strictest(&jurisdictions);
        Self {
            jurisdictions,
            merged_profile,
        }
    }

    /// Analyze a single audio asset.
    pub fn analyze_asset(&self, asset: &AudioAssetProfile) -> AssetAnalysis {
        let arousal = ArousalCoefficient::compute(
            asset.energy_density,
            asset.escalation_rate,
            asset.normalized_bpm,
            asset.celebration_delta,
            asset.dynamic_range,
        );

        let near_miss = NearMissDeceptionIndex::compute(
            asset.spectral_similarity_to_win,
            asset.anticipation_buildup,
            asset.resolve_disappointment,
            asset.reel_stop_delay,
        );

        let loss_disguise = LossDisguiseScore::compute(
            asset.spectral_similarity_loss_win,
            asset.positive_tonality,
            asset.celebratory_elements,
        );

        let temporal = TemporalDistortionFactor::compute(
            asset.loop_seamlessness,
            asset.tempo_stability,
            asset.silence_absence,
            asset.duration_inflation,
        );

        let metrics = RgaiMetrics::compute(
            arousal,
            near_miss,
            loss_disguise,
            temporal,
            self.merged_profile.ldw_suppression_required,
        );

        let per_jurisdiction: Vec<JurisdictionResult> = self
            .jurisdictions
            .iter()
            .map(|j| {
                let profile = j.profile();
                let violations = metrics.violations(&profile);
                JurisdictionResult {
                    jurisdiction: *j,
                    passes: violations.is_empty(),
                    violations,
                }
            })
            .collect();

        AssetAnalysis {
            asset_id: asset.id.clone(),
            asset_category: asset.category.clone(),
            metrics,
            per_jurisdiction,
        }
    }

    /// Analyze an entire game audio session (all assets + game-level checks).
    pub fn analyze_session(&self, session: &GameAudioSession) -> SessionAnalysisResult {
        let asset_analyses: Vec<AssetAnalysis> = session
            .assets
            .iter()
            .map(|a| self.analyze_asset(a))
            .collect();

        // Game-level aggregation
        let avg_arousal = if asset_analyses.is_empty() {
            0.0
        } else {
            asset_analyses
                .iter()
                .map(|a| a.metrics.arousal.value())
                .sum::<f64>()
                / asset_analyses.len() as f64
        };

        let max_loss_disguise = asset_analyses
            .iter()
            .map(|a| a.metrics.loss_disguise.value())
            .fold(0.0_f64, f64::max);

        let max_near_miss = asset_analyses
            .iter()
            .map(|a| a.metrics.near_miss_deception.value())
            .fold(0.0_f64, f64::max);

        let failing_asset_count = asset_analyses
            .iter()
            .filter(|a| a.per_jurisdiction.iter().any(|j| !j.passes))
            .count();

        let all_pass = failing_asset_count == 0;

        // Check game-level rules
        let mut game_level_violations = Vec::new();

        // Celebration duration check
        if session.max_celebration_duration_secs > self.merged_profile.max_celebration_duration_secs
        {
            game_level_violations.push(GameLevelViolation {
                rule: "max_celebration_duration".to_string(),
                description: format!(
                    "Longest win celebration ({:.1}s) exceeds limit ({:.1}s)",
                    session.max_celebration_duration_secs,
                    self.merged_profile.max_celebration_duration_secs,
                ),
                severity: ViolationSeverity::Critical,
            });
        }

        // LDW suppression check
        if self.merged_profile.ldw_suppression_required && !session.ldw_suppression_implemented {
            game_level_violations.push(GameLevelViolation {
                rule: "ldw_suppression".to_string(),
                description: "LDW (Loss Disguised as Win) audio suppression is required but not implemented".to_string(),
                severity: ViolationSeverity::Critical,
            });
        }

        // Near-miss enhancement check
        if self.merged_profile.near_miss_enhancement_prohibited
            && session.near_miss_audio_enhanced
        {
            game_level_violations.push(GameLevelViolation {
                rule: "near_miss_enhancement".to_string(),
                description: "Near-miss audio enhancement is prohibited in target jurisdictions"
                    .to_string(),
                severity: ViolationSeverity::Critical,
            });
        }

        // Cooling-off audio check
        if self.merged_profile.cooling_off_audio_required && !session.cooling_off_audio_present {
            game_level_violations.push(GameLevelViolation {
                rule: "cooling_off_audio".to_string(),
                description: format!(
                    "Cooling-off ambient audio required after {} minutes of play",
                    self.merged_profile.cooling_off_trigger_minutes
                ),
                severity: ViolationSeverity::Major,
            });
        }

        // Session time reminder audio
        if self.merged_profile.session_time_reminder_required
            && !session.session_time_reminder_audio_present
        {
            game_level_violations.push(GameLevelViolation {
                rule: "session_time_reminder".to_string(),
                description: format!(
                    "Session-time audio reminder required every {} minutes",
                    self.merged_profile.session_time_reminder_interval_minutes
                ),
                severity: ViolationSeverity::Major,
            });
        }

        let overall_pass = all_pass && game_level_violations.is_empty();

        SessionAnalysisResult {
            game_title: session.game_title.clone(),
            target_jurisdictions: self.jurisdictions.clone(),
            asset_analyses,
            game_level_violations,
            overall_pass,
            aggregate_arousal: avg_arousal,
            worst_loss_disguise: max_loss_disguise,
            worst_near_miss: max_near_miss,
            total_assets: session.assets.len(),
            failing_asset_count,
        }
    }

    pub fn jurisdictions(&self) -> &[Jurisdiction] {
        &self.jurisdictions
    }

    pub fn merged_profile(&self) -> &JurisdictionProfile {
        &self.merged_profile
    }
}

/// Analysis result for a single audio asset.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetAnalysis {
    pub asset_id: String,
    pub asset_category: String,
    pub metrics: RgaiMetrics,
    pub per_jurisdiction: Vec<JurisdictionResult>,
}

impl AssetAnalysis {
    pub fn passes_all(&self) -> bool {
        self.per_jurisdiction.iter().all(|j| j.passes)
    }
}

/// Per-jurisdiction pass/fail result with violation details.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JurisdictionResult {
    pub jurisdiction: Jurisdiction,
    pub passes: bool,
    pub violations: Vec<MetricViolation>,
}

/// Full session analysis result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionAnalysisResult {
    pub game_title: String,
    pub target_jurisdictions: Vec<Jurisdiction>,
    pub asset_analyses: Vec<AssetAnalysis>,
    pub game_level_violations: Vec<GameLevelViolation>,
    pub overall_pass: bool,
    pub aggregate_arousal: f64,
    pub worst_loss_disguise: f64,
    pub worst_near_miss: f64,
    pub total_assets: usize,
    pub failing_asset_count: usize,
}

/// A game-level compliance violation (not per-asset).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameLevelViolation {
    pub rule: String,
    pub description: String,
    pub severity: ViolationSeverity,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ViolationSeverity {
    /// Must fix before export — blocks export gate.
    Critical,
    /// Should fix — may cause regulatory issues.
    Major,
    /// Recommended improvement.
    Minor,
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{AudioAssetProfile, GameAudioSession};

    fn safe_asset(id: &str) -> AudioAssetProfile {
        AudioAssetProfile {
            id: id.to_string(),
            category: "ambient".to_string(),
            energy_density: 0.2,
            escalation_rate: 0.1,
            normalized_bpm: 0.15,
            celebration_delta: 0.1,
            dynamic_range: 0.2,
            spectral_similarity_to_win: 0.1,
            anticipation_buildup: 0.1,
            resolve_disappointment: 0.1,
            reel_stop_delay: 0.05,
            spectral_similarity_loss_win: 0.1,
            positive_tonality: 0.1,
            celebratory_elements: 0.0,
            loop_seamlessness: 0.2,
            tempo_stability: 0.3,
            silence_absence: 0.2,
            duration_inflation: 0.1,
        }
    }

    fn risky_asset(id: &str) -> AudioAssetProfile {
        AudioAssetProfile {
            id: id.to_string(),
            category: "win_celebration".to_string(),
            energy_density: 0.9,
            escalation_rate: 0.85,
            normalized_bpm: 0.8,
            celebration_delta: 0.9,
            dynamic_range: 0.7,
            spectral_similarity_to_win: 0.8,
            anticipation_buildup: 0.7,
            resolve_disappointment: 0.6,
            reel_stop_delay: 0.5,
            spectral_similarity_loss_win: 0.8,
            positive_tonality: 0.9,
            celebratory_elements: 0.85,
            loop_seamlessness: 0.8,
            tempo_stability: 0.9,
            silence_absence: 0.85,
            duration_inflation: 0.7,
        }
    }

    fn compliant_session() -> GameAudioSession {
        GameAudioSession {
            game_title: "Test Slot".to_string(),
            assets: vec![safe_asset("ambient_01"), safe_asset("reel_stop_01")],
            max_celebration_duration_secs: 3.0,
            ldw_suppression_implemented: true,
            near_miss_audio_enhanced: false,
            cooling_off_audio_present: true,
            session_time_reminder_audio_present: true,
        }
    }

    #[test]
    fn analyze_safe_asset_passes_ukgc() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let result = analyzer.analyze_asset(&safe_asset("test"));
        assert!(result.passes_all());
        assert_eq!(result.metrics.risk_rating, AddictionRiskRating::Low);
    }

    #[test]
    fn analyze_risky_asset_fails_ukgc() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let result = analyzer.analyze_asset(&risky_asset("danger"));
        assert!(!result.passes_all());
        // Should have violations in all metrics
        let ukgc_result = &result.per_jurisdiction[0];
        assert!(!ukgc_result.passes);
        assert!(ukgc_result.violations.len() >= 2);
    }

    #[test]
    fn analyze_risky_asset_may_pass_permissive() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Custom]);
        let result = analyzer.analyze_asset(&risky_asset("danger"));
        assert!(result.passes_all()); // permissive allows everything
    }

    #[test]
    fn session_analysis_compliant() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let result = analyzer.analyze_session(&compliant_session());
        assert!(result.overall_pass);
        assert_eq!(result.failing_asset_count, 0);
        assert!(result.game_level_violations.is_empty());
    }

    #[test]
    fn session_analysis_ldw_suppression_missing() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut session = compliant_session();
        session.ldw_suppression_implemented = false;
        let result = analyzer.analyze_session(&session);
        assert!(!result.overall_pass);
        assert!(result
            .game_level_violations
            .iter()
            .any(|v| v.rule == "ldw_suppression"));
    }

    #[test]
    fn session_analysis_celebration_too_long() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Sweden]);
        let mut session = compliant_session();
        session.max_celebration_duration_secs = 10.0; // Sweden limit = 4.0
        let result = analyzer.analyze_session(&session);
        assert!(!result.overall_pass);
        assert!(result
            .game_level_violations
            .iter()
            .any(|v| v.rule == "max_celebration_duration"));
    }

    #[test]
    fn session_analysis_near_miss_enhanced_prohibited() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut session = compliant_session();
        session.near_miss_audio_enhanced = true;
        let result = analyzer.analyze_session(&session);
        assert!(!result.overall_pass);
    }

    #[test]
    fn session_analysis_cooling_off_missing() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Ukgc]);
        let mut session = compliant_session();
        session.cooling_off_audio_present = false;
        let result = analyzer.analyze_session(&session);
        assert!(!result.overall_pass);
    }

    #[test]
    fn multi_jurisdiction_strictest_wins() {
        let analyzer =
            RgaiAnalyzer::new(vec![Jurisdiction::Ukgc, Jurisdiction::Mga, Jurisdiction::Sweden]);
        // An asset that passes MGA but fails Sweden/UKGC
        let mut asset = safe_asset("moderate");
        asset.energy_density = 0.95;
        asset.escalation_rate = 0.9;
        asset.normalized_bpm = 0.85;
        asset.celebration_delta = 0.8;
        asset.dynamic_range = 0.7;
        let result = analyzer.analyze_asset(&asset);
        // Should fail at least Sweden (strictest arousal = 0.55)
        let sweden = result
            .per_jurisdiction
            .iter()
            .find(|j| j.jurisdiction == Jurisdiction::Sweden)
            .unwrap();
        assert!(!sweden.passes);
    }

    #[test]
    fn aggregate_metrics_computed() {
        let analyzer = RgaiAnalyzer::new(vec![Jurisdiction::Custom]);
        let session = GameAudioSession {
            game_title: "Test".to_string(),
            assets: vec![safe_asset("a"), risky_asset("b")],
            max_celebration_duration_secs: 3.0,
            ldw_suppression_implemented: true,
            near_miss_audio_enhanced: false,
            cooling_off_audio_present: true,
            session_time_reminder_audio_present: true,
        };
        let result = analyzer.analyze_session(&session);
        assert_eq!(result.total_assets, 2);
        assert!(result.aggregate_arousal > 0.0);
        assert!(result.worst_loss_disguise > 0.0);
    }
}
