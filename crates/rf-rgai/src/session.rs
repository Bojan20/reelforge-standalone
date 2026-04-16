//! Audio asset profiles and game session descriptors.
//!
//! These structs describe the audio characteristics of a slot game
//! for RGAI analysis. Values are typically computed by rf-aurexis
//! (spectral analysis) and passed through FFI.

use serde::{Deserialize, Serialize};

/// Profile of a single audio asset for RGAI analysis.
/// All feature values are normalized 0.0–1.0.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioAssetProfile {
    /// Unique asset identifier (e.g., FFNC name).
    pub id: String,
    /// Category: "ambient", "win_celebration", "reel_spin", "near_miss",
    /// "loss", "bonus_trigger", "ui_click", etc.
    pub category: String,

    // ── Arousal inputs ──
    /// Spectral energy concentration (0=sparse, 1=dense broadband)
    pub energy_density: f64,
    /// How fast audio intensity climbs over its duration
    pub escalation_rate: f64,
    /// BPM normalized: 0.5 = 120bpm baseline, 1.0 = 240bpm+
    pub normalized_bpm: f64,
    /// Loudness gap between win moment and ambient (0=same, 1=huge gap)
    pub celebration_delta: f64,
    /// Dynamic range: softest↔loudest within the asset
    pub dynamic_range: f64,

    // ── Near-miss deception inputs ──
    /// MFCC cosine similarity between this asset and win sounds
    pub spectral_similarity_to_win: f64,
    /// How quickly tension builds in this asset
    pub anticipation_buildup: f64,
    /// How briefly the "disappointment/loss reveal" segment plays (1=instant, gone fast)
    pub resolve_disappointment: f64,
    /// Whether last reel deliberately lingers (0=no, 1=max delay)
    pub reel_stop_delay: f64,

    // ── Loss-disguise inputs ──
    /// MFCC cosine similarity between loss sound and win sound
    pub spectral_similarity_loss_win: f64,
    /// Major key / bright timbre presence (0=dark/minor, 1=bright/major)
    pub positive_tonality: f64,
    /// Celebratory elements (fanfare, chimes, jingles) in this asset
    pub celebratory_elements: f64,

    // ── Temporal distortion inputs ──
    /// How imperceptible the loop point is (0=obvious, 1=seamless)
    pub loop_seamlessness: f64,
    /// BPM variation absence (0=lots of variation, 1=monotonous)
    pub tempo_stability: f64,
    /// Ratio of audio to silence in session (0=lots of silence, 1=wall-to-wall)
    pub silence_absence: f64,
    /// Whether durations are disproportionate (e.g., win 10x longer than loss)
    pub duration_inflation: f64,
}

impl AudioAssetProfile {
    /// A "clean" asset that should pass any jurisdiction.
    pub fn safe_default(id: &str, category: &str) -> Self {
        Self {
            id: id.to_string(),
            category: category.to_string(),
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
}

/// Describes an entire game's audio session for analysis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameAudioSession {
    pub game_title: String,
    pub assets: Vec<AudioAssetProfile>,

    // ── Game-level flags ──
    /// Duration (seconds) of the longest win celebration.
    pub max_celebration_duration_secs: f64,
    /// Whether LDW (Loss Disguised as Win) audio suppression is active.
    pub ldw_suppression_implemented: bool,
    /// Whether near-miss sounds are artificially enhanced beyond natural gameplay.
    pub near_miss_audio_enhanced: bool,
    /// Whether cooling-off ambient audio exists for extended sessions.
    pub cooling_off_audio_present: bool,
    /// Whether periodic session-time audio reminders are implemented.
    pub session_time_reminder_audio_present: bool,
}

/// Per-session analysis summary (returned from RgaiAnalyzer::analyze_session).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionAnalysis {
    pub overall_risk: super::metrics::AddictionRiskRating,
    pub passing_jurisdictions: Vec<super::jurisdiction::Jurisdiction>,
    pub failing_jurisdictions: Vec<super::jurisdiction::Jurisdiction>,
    pub critical_assets: Vec<String>,
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_default_has_low_values() {
        let asset = AudioAssetProfile::safe_default("test", "ambient");
        assert!(asset.energy_density <= 0.3);
        assert!(asset.celebratory_elements == 0.0);
        assert!(asset.reel_stop_delay < 0.1);
    }

    #[test]
    fn game_session_serializes() {
        let session = GameAudioSession {
            game_title: "Egyptian Riches".to_string(),
            assets: vec![AudioAssetProfile::safe_default("amb_01", "ambient")],
            max_celebration_duration_secs: 4.0,
            ldw_suppression_implemented: true,
            near_miss_audio_enhanced: false,
            cooling_off_audio_present: true,
            session_time_reminder_audio_present: true,
        };
        let json = serde_json::to_string(&session).unwrap();
        let parsed: GameAudioSession = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.game_title, "Egyptian Riches");
        assert_eq!(parsed.assets.len(), 1);
    }

    #[test]
    fn asset_profile_all_fields_serializable() {
        let asset = AudioAssetProfile {
            id: "win_tier_5".to_string(),
            category: "win_celebration".to_string(),
            energy_density: 0.9,
            escalation_rate: 0.8,
            normalized_bpm: 0.7,
            celebration_delta: 0.85,
            dynamic_range: 0.6,
            spectral_similarity_to_win: 0.95,
            anticipation_buildup: 0.7,
            resolve_disappointment: 0.3,
            reel_stop_delay: 0.2,
            spectral_similarity_loss_win: 0.4,
            positive_tonality: 0.8,
            celebratory_elements: 0.9,
            loop_seamlessness: 0.5,
            tempo_stability: 0.6,
            silence_absence: 0.7,
            duration_inflation: 0.8,
        };
        let json = serde_json::to_string_pretty(&asset).unwrap();
        assert!(json.contains("win_tier_5"));
        let roundtrip: AudioAssetProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(roundtrip.energy_density, 0.9);
    }
}
