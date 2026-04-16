//! PlayerStateVector, AudioAdaptation, RgIntervention.

use serde::{Deserialize, Serialize};

/// 8-dimensional Player State Vector
/// All dimensions are clamped 0.0–1.0
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayerStateVector {
    /// 0=calm/bored, 1=excited/stimulated
    pub arousal: f64,
    /// 0=frustrated/negative, 1=euphoric/positive
    pub valence: f64,
    /// 0=disengaged/about-to-leave, 1=deep-flow
    pub engagement: f64,
    /// 0=conservative, 1=reckless-chasing
    pub risk_tolerance: f64,
    /// 0=content, 1=tilted
    pub frustration: f64,
    /// 0=nothing-expected, 1=big-win-anticipated
    pub anticipation: f64,
    /// 0=fresh, 1=exhausted
    pub fatigue: f64,
    /// 0=staying, 1=about-to-quit
    pub churn_probability: f64,
}

impl PlayerStateVector {
    /// Neutral state — new session baseline
    pub fn neutral() -> Self {
        Self {
            arousal: 0.3,
            valence: 0.5,
            engagement: 0.6,
            risk_tolerance: 0.3,
            frustration: 0.0,
            anticipation: 0.2,
            fatigue: 0.0,
            churn_probability: 0.1,
        }
    }

    /// Responsible gaming risk score (0.0–1.0, composite)
    pub fn rg_risk_score(&self) -> f64 {
        (self.risk_tolerance * 0.30
            + self.frustration * 0.25
            + self.churn_probability * 0.20
            + (1.0 - self.engagement) * 0.15
            + self.fatigue * 0.10)
            .clamp(0.0, 1.0)
    }

    /// Classify into risk tier
    pub fn risk_level(&self) -> RiskLevel {
        let score = self.rg_risk_score();
        if score > 0.70 { RiskLevel::High }
        else if score > 0.50 { RiskLevel::Elevated }
        else if score > 0.30 { RiskLevel::Moderate }
        else { RiskLevel::Low }
    }

    /// Clamp all fields into [0.0, 1.0]
    pub fn clamped(self) -> Self {
        Self {
            arousal:           self.arousal.clamp(0.0, 1.0),
            valence:           self.valence.clamp(0.0, 1.0),
            engagement:        self.engagement.clamp(0.0, 1.0),
            risk_tolerance:    self.risk_tolerance.clamp(0.0, 1.0),
            frustration:       self.frustration.clamp(0.0, 1.0),
            anticipation:      self.anticipation.clamp(0.0, 1.0),
            fatigue:           self.fatigue.clamp(0.0, 1.0),
            churn_probability: self.churn_probability.clamp(0.0, 1.0),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RiskLevel {
    Low,
    Moderate,
    Elevated,
    High,
}

/// Computed audio adaptation parameters — map directly to RTPC values
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioAdaptation {
    /// Music BPM multiplier: 0.7–1.3 (±30% from base)
    pub music_bpm_multiplier: f64,
    /// Reverb depth: 0.0 (dry/intimate) – 1.0 (wet/grand)
    pub reverb_depth: f64,
    /// Dynamic compression ratio: 1.0 (none) – 8.0 (heavy pumping)
    pub compression_ratio: f64,
    /// Win sound magnitude: 0.5 (subdued) – 2.0 (amplified)
    pub win_magnitude_bias: f64,
    /// Near-miss tension level: 0.0 – 1.0
    pub tension_calibration: f64,
    /// Volume envelope dynamic range: 0.0 (flat) – 1.0 (full dynamic)
    pub volume_envelope_shape: f64,
    /// High-frequency brightness: 0.0 (dark/warm) – 1.0 (bright/crisp)
    pub hf_brightness: f64,
    /// Stereo/spatial width: 0.0 (mono/intimate) – 1.0 (wide/epic)
    pub spatial_width: f64,
    /// Active RG intervention (if any)
    pub rg_intervention: Option<RgIntervention>,
}

impl AudioAdaptation {
    /// Neutral adaptation — no modification to base audio
    pub fn neutral() -> Self {
        Self {
            music_bpm_multiplier: 1.0,
            reverb_depth: 0.5,
            compression_ratio: 2.0,
            win_magnitude_bias: 1.0,
            tension_calibration: 0.5,
            volume_envelope_shape: 0.7,
            hf_brightness: 0.7,
            spatial_width: 0.5,
            rg_intervention: None,
        }
    }

    /// Compute adaptation from Player State Vector
    pub fn from_state(state: &PlayerStateVector, rg_enabled: bool) -> Self {
        let rg_risk = state.rg_risk_score();

        // ─── Responsible Gaming override ────────────────────────────────────
        if rg_enabled && rg_risk > 0.70 {
            return Self {
                music_bpm_multiplier: 0.80,  // slower music = calming
                reverb_depth: 0.70,           // more reverb = spacious, less stimulating
                compression_ratio: 1.5,       // less dense = less exciting
                win_magnitude_bias: 0.50,     // subdued win sounds
                tension_calibration: 0.10,    // minimal near-miss tension
                volume_envelope_shape: 0.30,  // compressed dynamics
                hf_brightness: 0.30,          // dark/warm = calming
                spatial_width: 0.40,          // intimate = less overwhelming
                rg_intervention: Some(RgIntervention::Active {
                    trigger_dimension: "churn_probability + frustration".to_string(),
                    rg_score: rg_risk,
                }),
            };
        }

        if rg_enabled && rg_risk > 0.50 {
            return Self {
                music_bpm_multiplier: 0.92,
                reverb_depth: 0.62,
                compression_ratio: 2.0,
                win_magnitude_bias: 0.75,
                tension_calibration: 0.25,
                volume_envelope_shape: 0.50,
                hf_brightness: 0.50,
                spatial_width: 0.45,
                rg_intervention: Some(RgIntervention::Subtle {
                    rg_score: rg_risk,
                }),
            };
        }

        // ─── Normal adaptive mode ────────────────────────────────────────────

        // BPM: faster when engaged+aroused, slower when fatigued/frustrated
        let bpm = (1.0
            + (state.arousal - 0.5) * 0.30
            + (state.valence - 0.5) * 0.10
            - state.fatigue * 0.15
            - state.frustration * 0.10)
            .clamp(0.70, 1.30);

        // Reverb: more reverb during peak moments, intimate during flow
        let reverb = (0.30
            + state.arousal * 0.40
            + state.anticipation * 0.20
            + (1.0 - state.engagement) * 0.10)
            .clamp(0.20, 1.0);

        // Compression: denser during high engagement, relaxed when fatigued
        let compression = (1.5
            + state.engagement * 3.0
            + state.arousal * 1.5
            - state.fatigue * 1.0)
            .clamp(1.0, 8.0);

        // Win magnitude: bigger when engaged, smaller when fatigued/frustrated
        let win_bias = (1.0
            + state.engagement * 0.40
            + state.valence * 0.30
            - state.fatigue * 0.40
            - state.frustration * 0.25)
            .clamp(0.50, 2.0);

        // Tension: match engagement, reduce if frustration is high (avoid tilt)
        let tension = (state.anticipation * 0.50
            + state.arousal * 0.30
            - state.frustration * 0.50)
            .clamp(0.0, 1.0);

        // Volume envelope: full range in flow, compressed when fatigued
        let vol_shape = (0.80
            - state.fatigue * 0.30
            - state.frustration * 0.20
            + state.engagement * 0.10)
            .clamp(0.30, 1.0);

        // HF brightness: bright when fresh/excited, dark when fatigued
        let hf = (0.70
            + (state.arousal - 0.50) * 0.20
            - state.fatigue * 0.40)
            .clamp(0.20, 1.0);

        // Spatial width: wide during peaks/features, intimate during normal play
        let spatial = (0.40
            + state.arousal * 0.30
            + state.anticipation * 0.20)
            .clamp(0.20, 1.0);

        Self {
            music_bpm_multiplier: bpm,
            reverb_depth: reverb,
            compression_ratio: compression,
            win_magnitude_bias: win_bias,
            tension_calibration: tension,
            volume_envelope_shape: vol_shape,
            hf_brightness: hf,
            spatial_width: spatial,
            rg_intervention: None,
        }
    }
}

/// Active responsible gaming intervention descriptor
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "level", rename_all = "snake_case")]
pub enum RgIntervention {
    /// Full active intervention — high-risk player detected
    Active {
        trigger_dimension: String,
        rg_score: f64,
    },
    /// Subtle modulation — elevated-risk player
    Subtle {
        rg_score: f64,
    },
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_neutral_state_fields_in_range() {
        let s = PlayerStateVector::neutral();
        for v in [s.arousal, s.valence, s.engagement, s.risk_tolerance,
                  s.frustration, s.anticipation, s.fatigue, s.churn_probability] {
            assert!((0.0..=1.0).contains(&v));
        }
    }

    #[test]
    fn test_rg_risk_score_bounds() {
        let s = PlayerStateVector::neutral();
        let score = s.rg_risk_score();
        assert!((0.0..=1.0).contains(&score));
    }

    #[test]
    fn test_high_risk_state_triggers_rg() {
        let s = PlayerStateVector {
            arousal: 0.9,
            valence: 0.1,
            engagement: 0.1,
            risk_tolerance: 1.0,
            frustration: 1.0,
            anticipation: 0.5,
            fatigue: 0.8,
            churn_probability: 1.0,
        };
        assert!(s.rg_risk_score() > 0.70);
        assert_eq!(s.risk_level(), RiskLevel::High);
    }

    #[test]
    fn test_adaptation_neutral_state() {
        let s = PlayerStateVector::neutral();
        let adapt = AudioAdaptation::from_state(&s, false);
        assert!(adapt.rg_intervention.is_none());
        // BPM should be near 1.0 for neutral state
        assert!((0.85..=1.15).contains(&adapt.music_bpm_multiplier));
    }

    #[test]
    fn test_adaptation_rg_active_on_high_risk() {
        let s = PlayerStateVector {
            arousal: 0.9,
            valence: 0.1,
            engagement: 0.1,
            risk_tolerance: 1.0,
            frustration: 1.0,
            anticipation: 0.5,
            fatigue: 0.8,
            churn_probability: 1.0,
        };
        let adapt = AudioAdaptation::from_state(&s, true);
        assert!(matches!(adapt.rg_intervention, Some(RgIntervention::Active { .. })));
        // BPM should be reduced
        assert!(adapt.music_bpm_multiplier < 0.90);
    }

    #[test]
    fn test_adaptation_no_rg_when_disabled() {
        let s = PlayerStateVector {
            risk_tolerance: 1.0,
            frustration: 1.0,
            churn_probability: 1.0,
            ..PlayerStateVector::neutral()
        };
        let adapt = AudioAdaptation::from_state(&s, false);
        // RG disabled — no intervention even for high-risk state
        assert!(adapt.rg_intervention.is_none());
    }

    #[test]
    fn test_all_adaptation_fields_in_range() {
        let s = PlayerStateVector::neutral();
        let a = AudioAdaptation::from_state(&s, false);
        assert!((0.70..=1.30).contains(&a.music_bpm_multiplier));
        assert!((0.0..=1.0).contains(&a.reverb_depth));
        assert!((1.0..=8.0).contains(&a.compression_ratio));
        assert!((0.50..=2.0).contains(&a.win_magnitude_bias));
        assert!((0.0..=1.0).contains(&a.tension_calibration));
        assert!((0.0..=1.0).contains(&a.volume_envelope_shape));
        assert!((0.0..=1.0).contains(&a.hf_brightness));
        assert!((0.0..=1.0).contains(&a.spatial_width));
    }
}
