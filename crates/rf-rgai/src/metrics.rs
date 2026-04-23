//! Core RGAI metrics — the quantitative backbone of compliance analysis.

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// T1.1: Arousal Coefficient (0.0–1.0)
// ═══════════════════════════════════════════════════════════════════════════

/// Measures how stimulating the audio is — higher = more arousing.
///
/// Formula: weighted average of
///   0.30 × energy_density     — spectral energy concentration
///   0.20 × escalation_rate    — how fast audio intensity climbs
///   0.20 × normalized_bpm     — tempo relative to 120bpm baseline
///   0.15 × celebration_delta  — loudness gap: win vs ambient
///   0.15 × dynamic_range      — softest↔loudest moment gap
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ArousalCoefficient(f64);

impl ArousalCoefficient {
    pub fn compute(
        energy_density: f64,
        escalation_rate: f64,
        normalized_bpm: f64,
        celebration_delta: f64,
        dynamic_range: f64,
    ) -> Self {
        let raw = energy_density * 0.30
            + escalation_rate * 0.20
            + normalized_bpm * 0.20
            + celebration_delta * 0.15
            + dynamic_range * 0.15;
        Self(raw.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f64 {
        self.0
    }

    /// Quick classification for UI display.
    pub fn level(&self) -> ArousalLevel {
        if self.0 > 0.8 {
            ArousalLevel::Extreme
        } else if self.0 > 0.6 {
            ArousalLevel::High
        } else if self.0 > 0.4 {
            ArousalLevel::Moderate
        } else if self.0 > 0.2 {
            ArousalLevel::Low
        } else {
            ArousalLevel::Minimal
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ArousalLevel {
    Minimal,
    Low,
    Moderate,
    High,
    Extreme,
}

// ═══════════════════════════════════════════════════════════════════════════
// T1.2: Near-Miss Deception Index (0.0–1.0)
// ═══════════════════════════════════════════════════════════════════════════

/// Measures how much a near-miss sound deceives the player into thinking they
/// almost won. Higher = more deceptive.
///
/// Formula:
///   0.40 × spectral_similarity    — MFCC cosine distance (near-miss↔win)
///   0.30 × anticipation_buildup   — how fast tension ramps in near-miss
///   0.20 × resolve_disappointment — how briefly the "loss reveal" plays
///   0.10 × reel_stop_delay        — whether last reel deliberately lingers
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct NearMissDeceptionIndex(f64);

impl NearMissDeceptionIndex {
    pub fn compute(
        spectral_similarity: f64,
        anticipation_buildup: f64,
        resolve_disappointment: f64,
        reel_stop_delay: f64,
    ) -> Self {
        let raw = spectral_similarity * 0.40
            + anticipation_buildup * 0.30
            + resolve_disappointment * 0.20
            + reel_stop_delay * 0.10;
        Self(raw.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// T1.3: Loss-Disguise Score (0.0–1.0)
// ═══════════════════════════════════════════════════════════════════════════

/// Measures how much a loss sounds like a win (LDW — Loss Disguised as Win).
/// This is the single most scrutinized metric by UKGC.
///
/// Formula:
///   0.50 × spectral_similarity    — MFCC cosine (loss↔win)
///   0.25 × positive_tonality      — major key, bright timbre in loss sound
///   0.25 × celebratory_elements   — fanfare/chimes/jingles present in loss
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct LossDisguiseScore(f64);

impl LossDisguiseScore {
    pub fn compute(
        spectral_similarity: f64,
        positive_tonality: f64,
        celebratory_elements: f64,
    ) -> Self {
        let raw = spectral_similarity * 0.50
            + positive_tonality * 0.25
            + celebratory_elements * 0.25;
        Self(raw.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// T1.3b: Temporal Distortion Factor (0.0–1.0)
// ═══════════════════════════════════════════════════════════════════════════

/// Measures whether audio warps the player's perception of time passing.
/// High-tempo loops, seamless ambient beds, and absence of natural pauses
/// all contribute to temporal distortion.
///
/// Formula:
///   0.35 × loop_seamlessness  — how imperceptible the ambient loop point is
///   0.25 × tempo_stability    — absence of BPM variation (monotony induces flow)
///   0.25 × silence_absence    — ratio of audio coverage to total session time
///   0.15 × duration_inflation — whether win celebrations are disproportionately long
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct TemporalDistortionFactor(f64);

impl TemporalDistortionFactor {
    pub fn compute(
        loop_seamlessness: f64,
        tempo_stability: f64,
        silence_absence: f64,
        duration_inflation: f64,
    ) -> Self {
        let raw = loop_seamlessness * 0.35
            + tempo_stability * 0.25
            + silence_absence * 0.25
            + duration_inflation * 0.15;
        Self(raw.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Composite: Addiction Risk Rating
// ═══════════════════════════════════════════════════════════════════════════

/// Composite risk rating derived from all four metrics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum AddictionRiskRating {
    /// All metrics < 0.3
    Low,
    /// All metrics < 0.6, none exceeding near-miss/LDS thresholds
    Medium,
    /// Any metric > 0.6
    High,
    /// Any metric > 0.8 in a jurisdiction that mandates suppression
    Prohibited,
}

impl AddictionRiskRating {
    /// Is this rating exportable (i.e., not blocked by compliance)?
    pub fn is_exportable(&self) -> bool {
        !matches!(self, Self::Prohibited)
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Low => "LOW",
            Self::Medium => "MEDIUM",
            Self::High => "HIGH",
            Self::Prohibited => "PROHIBITED",
        }
    }

    pub fn color_hex(&self) -> &'static str {
        match self {
            Self::Low => "#22c55e",
            Self::Medium => "#eab308",
            Self::High => "#f97316",
            Self::Prohibited => "#ef4444",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Aggregated metrics bundle
// ═══════════════════════════════════════════════════════════════════════════

/// All RGAI metrics for a single audio asset or entire game session.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RgaiMetrics {
    pub arousal: ArousalCoefficient,
    pub near_miss_deception: NearMissDeceptionIndex,
    pub loss_disguise: LossDisguiseScore,
    pub temporal_distortion: TemporalDistortionFactor,
    pub risk_rating: AddictionRiskRating,
}

impl RgaiMetrics {
    /// Compute the composite risk rating from individual metrics,
    /// optionally considering jurisdiction-specific thresholds.
    pub fn compute(
        arousal: ArousalCoefficient,
        near_miss_deception: NearMissDeceptionIndex,
        loss_disguise: LossDisguiseScore,
        temporal_distortion: TemporalDistortionFactor,
        jurisdiction_requires_suppression: bool,
    ) -> Self {
        let max_metric = arousal
            .value()
            .max(near_miss_deception.value())
            .max(loss_disguise.value())
            .max(temporal_distortion.value());

        let risk_rating = if max_metric > 0.8 && jurisdiction_requires_suppression {
            AddictionRiskRating::Prohibited
        } else if max_metric > 0.6 {
            AddictionRiskRating::High
        } else if arousal.value() < 0.3
            && near_miss_deception.value() < 0.2
            && loss_disguise.value() < 0.2
            && temporal_distortion.value() < 0.3
        {
            AddictionRiskRating::Low
        } else {
            AddictionRiskRating::Medium
        };

        Self {
            arousal,
            near_miss_deception,
            loss_disguise,
            temporal_distortion,
            risk_rating,
        }
    }

    /// Highest single metric value — the "weakest link" for compliance.
    pub fn worst_metric(&self) -> (String, f64) {
        let candidates = [
            ("arousal", self.arousal.value()),
            ("near_miss_deception", self.near_miss_deception.value()),
            ("loss_disguise", self.loss_disguise.value()),
            ("temporal_distortion", self.temporal_distortion.value()),
        ];
        let (name, val) = candidates
            .into_iter()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap())
            .unwrap();
        (name.to_string(), val)
    }

    /// Check whether these metrics pass a specific jurisdiction's thresholds.
    pub fn passes_jurisdiction(
        &self,
        profile: &super::jurisdiction::JurisdictionProfile,
    ) -> bool {
        self.arousal.value() <= profile.max_arousal
            && self.near_miss_deception.value() <= profile.max_near_miss_deception
            && self.loss_disguise.value() <= profile.max_loss_disguise
            && self.temporal_distortion.value() <= profile.max_temporal_distortion
    }

    /// Return all violations for a given jurisdiction.
    pub fn violations(
        &self,
        profile: &super::jurisdiction::JurisdictionProfile,
    ) -> Vec<MetricViolation> {
        let mut v = Vec::new();
        if self.arousal.value() > profile.max_arousal {
            v.push(MetricViolation {
                metric: "arousal".to_string(),
                actual: self.arousal.value(),
                threshold: profile.max_arousal,
                excess: self.arousal.value() - profile.max_arousal,
            });
        }
        if self.near_miss_deception.value() > profile.max_near_miss_deception {
            v.push(MetricViolation {
                metric: "near_miss_deception".to_string(),
                actual: self.near_miss_deception.value(),
                threshold: profile.max_near_miss_deception,
                excess: self.near_miss_deception.value() - profile.max_near_miss_deception,
            });
        }
        if self.loss_disguise.value() > profile.max_loss_disguise {
            v.push(MetricViolation {
                metric: "loss_disguise".to_string(),
                actual: self.loss_disguise.value(),
                threshold: profile.max_loss_disguise,
                excess: self.loss_disguise.value() - profile.max_loss_disguise,
            });
        }
        if self.temporal_distortion.value() > profile.max_temporal_distortion {
            v.push(MetricViolation {
                metric: "temporal_distortion".to_string(),
                actual: self.temporal_distortion.value(),
                threshold: profile.max_temporal_distortion,
                excess: self.temporal_distortion.value() - profile.max_temporal_distortion,
            });
        }
        v
    }
}

/// A single metric exceeding a jurisdiction threshold.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MetricViolation {
    pub metric: String,
    pub actual: f64,
    pub threshold: f64,
    pub excess: f64,
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::jurisdiction::JurisdictionProfile;

    #[test]
    fn arousal_coefficient_clamping() {
        let ac = ArousalCoefficient::compute(1.0, 1.0, 1.0, 1.0, 1.0);
        assert_eq!(ac.value(), 1.0);

        let ac = ArousalCoefficient::compute(0.0, 0.0, 0.0, 0.0, 0.0);
        assert_eq!(ac.value(), 0.0);
    }

    #[test]
    fn arousal_coefficient_weighted() {
        // energy_density dominates (0.30 weight)
        let ac = ArousalCoefficient::compute(1.0, 0.0, 0.0, 0.0, 0.0);
        assert!((ac.value() - 0.30).abs() < 1e-10);
    }

    #[test]
    fn arousal_levels() {
        assert_eq!(ArousalCoefficient::compute(0.0, 0.0, 0.0, 0.0, 0.0).level(), ArousalLevel::Minimal);
        assert_eq!(ArousalCoefficient::compute(1.0, 1.0, 1.0, 1.0, 1.0).level(), ArousalLevel::Extreme);
        assert_eq!(ArousalCoefficient::compute(0.5, 0.5, 0.5, 0.5, 0.5).level(), ArousalLevel::Moderate);
    }

    #[test]
    fn near_miss_deception_weighted() {
        let nmdi = NearMissDeceptionIndex::compute(1.0, 0.0, 0.0, 0.0);
        assert!((nmdi.value() - 0.40).abs() < 1e-10);
    }

    #[test]
    fn loss_disguise_weighted() {
        let lds = LossDisguiseScore::compute(1.0, 0.0, 0.0);
        assert!((lds.value() - 0.50).abs() < 1e-10);
    }

    #[test]
    fn temporal_distortion_weighted() {
        let td = TemporalDistortionFactor::compute(1.0, 0.0, 0.0, 0.0);
        assert!((td.value() - 0.35).abs() < 1e-10);
    }

    #[test]
    fn risk_rating_low() {
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(0.1, 0.1, 0.1, 0.1, 0.1),
            NearMissDeceptionIndex::compute(0.1, 0.1, 0.1, 0.1),
            LossDisguiseScore::compute(0.1, 0.1, 0.1),
            TemporalDistortionFactor::compute(0.1, 0.1, 0.1, 0.1),
            false,
        );
        assert_eq!(m.risk_rating, AddictionRiskRating::Low);
        assert!(m.risk_rating.is_exportable());
    }

    #[test]
    fn risk_rating_high() {
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(0.9, 0.8, 0.7, 0.6, 0.5),
            NearMissDeceptionIndex::compute(0.3, 0.3, 0.3, 0.3),
            LossDisguiseScore::compute(0.3, 0.3, 0.3),
            TemporalDistortionFactor::compute(0.3, 0.3, 0.3, 0.3),
            false,
        );
        assert_eq!(m.risk_rating, AddictionRiskRating::High);
    }

    #[test]
    fn risk_rating_prohibited_with_suppression() {
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(1.0, 1.0, 1.0, 1.0, 1.0),
            NearMissDeceptionIndex::compute(0.1, 0.1, 0.1, 0.1),
            LossDisguiseScore::compute(0.1, 0.1, 0.1),
            TemporalDistortionFactor::compute(0.1, 0.1, 0.1, 0.1),
            true,
        );
        assert_eq!(m.risk_rating, AddictionRiskRating::Prohibited);
        assert!(!m.risk_rating.is_exportable());
    }

    #[test]
    fn worst_metric_identifies_highest() {
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(0.2, 0.2, 0.2, 0.2, 0.2),
            NearMissDeceptionIndex::compute(0.9, 0.9, 0.9, 0.9),
            LossDisguiseScore::compute(0.1, 0.1, 0.1),
            TemporalDistortionFactor::compute(0.1, 0.1, 0.1, 0.1),
            false,
        );
        let (name, _) = m.worst_metric();
        assert_eq!(name, "near_miss_deception");
    }

    #[test]
    fn violations_detected() {
        let profile = JurisdictionProfile::ukgc();
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(1.0, 1.0, 1.0, 1.0, 1.0), // way over
            NearMissDeceptionIndex::compute(0.1, 0.1, 0.1, 0.1),   // safe
            LossDisguiseScore::compute(0.1, 0.1, 0.1),              // safe
            TemporalDistortionFactor::compute(0.1, 0.1, 0.1, 0.1),  // safe
            false,
        );
        let v = m.violations(&profile);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].metric, "arousal");
    }

    #[test]
    fn passes_jurisdiction_when_clean() {
        let profile = JurisdictionProfile::ukgc();
        let m = RgaiMetrics::compute(
            ArousalCoefficient::compute(0.2, 0.2, 0.2, 0.2, 0.2),
            NearMissDeceptionIndex::compute(0.2, 0.2, 0.2, 0.2),
            LossDisguiseScore::compute(0.2, 0.2, 0.2),
            TemporalDistortionFactor::compute(0.2, 0.2, 0.2, 0.2),
            false,
        );
        assert!(m.passes_jurisdiction(&profile));
    }

    #[test]
    fn metric_violation_has_excess() {
        let v = MetricViolation {
            metric: "arousal".to_string(),
            actual: 0.75,
            threshold: 0.60,
            excess: 0.15,
        };
        assert!((v.excess - 0.15).abs() < 1e-10);
    }
}
