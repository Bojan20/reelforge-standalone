//! PAR+ Extended Format — T2.7
//!
//! PAR+ is FluxForge's extension of the standard PAR format.
//! It adds conditional trigger probability matrices, win multiplier
//! distributions, session volatility metrics, and near-miss rate data
//! that standard PAR documents don't carry.
//!
//! ## PAR+ JSON Schema Extension
//!
//! A PAR+ document is a standard PAR JSON with an additional `par_plus` key:
//!
//! ```json
//! {
//!   // ... all standard PAR fields ...
//!   "par_plus": {
//!     "version": "1.0",
//!     "feature_trigger_matrices": [...],
//!     "win_multiplier_distributions": [...],
//!     "session_volatility": { ... },
//!     "near_miss_rates": { ... }
//!   }
//! }
//! ```
//!
//! PAR+ data is OPTIONAL — missing fields degrade gracefully.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURE TRIGGER MATRIX
// ═══════════════════════════════════════════════════════════════════════════════

/// Scatter-count conditional trigger probabilities.
/// Maps scatter count (as string "2", "3", "4", "5") → probability per spin.
pub type ScatterCountProbabilities = HashMap<String, f64>;

/// Per-reel landing probabilities for trigger symbol.
/// Index 0 = reel 0 (leftmost), length must match ParDocument.reels.
pub type PerReelProbabilities = Vec<f64>;

/// Detailed feature trigger data — extends ParFeature with conditional probabilities
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureTriggerMatrix {
    /// Feature name — matches ParFeature.name or feature_type
    pub feature_name: String,

    /// P(trigger | scatter_count = n) for each scatter count n
    #[serde(default)]
    pub scatter_count_probs: ScatterCountProbabilities,

    /// Per-reel trigger symbol landing probability (0.0–1.0 each)
    #[serde(default)]
    pub per_reel_probs: PerReelProbabilities,

    /// Probability of retriggering during feature (0.0 if no retrigger)
    #[serde(default)]
    pub retrigger_probability: f64,

    /// Average feature duration in spins
    #[serde(default)]
    pub avg_duration_spins: f64,

    /// Multiplier applied to all wins during feature (1.0 = none)
    #[serde(default = "default_one")]
    pub win_multiplier: f64,

    /// Average win multiplier from this feature (relative to base bet)
    #[serde(default)]
    pub avg_total_multiplier: f64,
}

fn default_one() -> f64 { 1.0 }

impl FeatureTriggerMatrix {
    /// Expected triggers per spin (scalar, ignoring conditional structure)
    pub fn expected_trigger_rate(&self) -> f64 {
        if !self.scatter_count_probs.is_empty() {
            self.scatter_count_probs.values().sum()
        } else {
            0.0
        }
    }

    /// Does this feature have per-reel detail?
    pub fn has_reel_detail(&self) -> bool {
        !self.per_reel_probs.is_empty()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIN MULTIPLIER DISTRIBUTION
// ═══════════════════════════════════════════════════════════════════════════════

/// A single bucket in a win multiplier histogram
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinMultiplierBucket {
    /// Lower bound (inclusive) in x-bet units
    pub from_multiplier: f64,
    /// Upper bound (exclusive) in x-bet units
    pub to_multiplier: f64,
    /// Probability of falling in this bucket (among all triggered occurrences)
    pub probability: f64,
}

/// Full win multiplier distribution for a feature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinMultiplierDistribution {
    /// Feature name — matches FeatureTriggerMatrix.feature_name
    pub feature_name: String,

    /// Histogram buckets (must sum to ~1.0)
    #[serde(default)]
    pub buckets: Vec<WinMultiplierBucket>,

    /// Distribution mean (x-bet)
    #[serde(default)]
    pub mean: f64,

    /// Standard deviation (x-bet)
    #[serde(default)]
    pub std_dev: f64,

    /// 95th percentile (x-bet)
    #[serde(default)]
    pub p95: f64,

    /// 99th percentile (x-bet)
    #[serde(default)]
    pub p99: f64,

    /// Absolute maximum observed (x-bet)
    #[serde(default)]
    pub max_observed: f64,
}

impl WinMultiplierDistribution {
    /// Verify buckets sum to approximately 1.0
    pub fn is_normalized(&self) -> bool {
        if self.buckets.is_empty() { return true; }
        let sum: f64 = self.buckets.iter().map(|b| b.probability).sum();
        (sum - 1.0).abs() < 0.01
    }

    /// Probability of win exceeding threshold (x-bet)
    pub fn prob_exceeding(&self, threshold: f64) -> f64 {
        self.buckets.iter()
            .filter(|b| b.from_multiplier >= threshold)
            .map(|b| b.probability)
            .sum()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SESSION VOLATILITY METRICS
// ═══════════════════════════════════════════════════════════════════════════════

/// Session-level volatility statistics (from extended batch sim or studio data)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SessionVolatilityMetrics {
    /// RTP standard deviation across 100-spin sessions (%)
    #[serde(default)]
    pub rtp_std_dev: f64,

    /// 10th percentile RTP for 100-spin session (%)
    #[serde(default)]
    pub session_rtp_p10: f64,

    /// 50th percentile (median) RTP for 100-spin session (%)
    #[serde(default)]
    pub session_rtp_p50: f64,

    /// 90th percentile RTP for 100-spin session (%)
    #[serde(default)]
    pub session_rtp_p90: f64,

    /// Average spins between bonus triggers
    #[serde(default)]
    pub spins_per_bonus_avg: f64,

    /// 99th percentile maximum consecutive loss streak
    #[serde(default)]
    pub consecutive_loss_p99: u32,

    /// Average session RTP drain per 100 spins at 5% hold
    #[serde(default)]
    pub theoretical_drain_100: f64,
}

impl SessionVolatilityMetrics {
    /// UKGC compliance: max consecutive loss streak must not exceed 200
    pub fn passes_ukgc_loss_streak(&self) -> bool {
        self.consecutive_loss_p99 == 0 || self.consecutive_loss_p99 <= 200
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEAR-MISS RATES
// ═══════════════════════════════════════════════════════════════════════════════

/// Near-miss configuration rates
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NearMissRates {
    /// Named near-miss configurations → probability per spin
    /// Keys: e.g. "two_scatter", "two_wild_expanding", "bonus_symbol_two"
    #[serde(default)]
    pub rates: HashMap<String, f64>,

    /// Ratio of near-miss events to actual triggers (across all features)
    /// Regulators check: must be realistic (not artificially inflated)
    #[serde(default)]
    pub near_miss_to_trigger_ratio: f64,

    /// If true, studio certifies near-miss rates are mathematically derived
    /// (not manipulated for psychological effect)
    #[serde(default)]
    pub mathematically_fair: bool,
}

impl NearMissRates {
    /// Total near-miss rate per spin
    pub fn total_rate(&self) -> f64 {
        self.rates.values().sum()
    }

    /// MGA compliance: near-miss ratio must be ≤ 12
    pub fn passes_mga_ratio_check(&self) -> bool {
        self.near_miss_to_trigger_ratio <= 12.0 || self.near_miss_to_trigger_ratio == 0.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAR+ EXTENSION (aggregates all above)
// ═══════════════════════════════════════════════════════════════════════════════

/// PAR+ extension block — lives at `document["par_plus"]`
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ParPlusExtension {
    /// Format version string
    #[serde(default = "default_version")]
    pub version: String,

    /// Detailed trigger matrices per feature
    #[serde(default)]
    pub feature_trigger_matrices: Vec<FeatureTriggerMatrix>,

    /// Win multiplier distributions per feature
    #[serde(default)]
    pub win_multiplier_distributions: Vec<WinMultiplierDistribution>,

    /// Session-level volatility metrics
    #[serde(default)]
    pub session_volatility: SessionVolatilityMetrics,

    /// Near-miss configuration rates
    #[serde(default)]
    pub near_miss_rates: NearMissRates,
}

fn default_version() -> String { "1.0".to_string() }

impl ParPlusExtension {
    /// Get trigger matrix for a named feature (by feature_name)
    pub fn trigger_matrix(&self, name: &str) -> Option<&FeatureTriggerMatrix> {
        self.feature_trigger_matrices.iter()
            .find(|m| m.feature_name.eq_ignore_ascii_case(name))
    }

    /// Get win distribution for a named feature
    pub fn win_distribution(&self, name: &str) -> Option<&WinMultiplierDistribution> {
        self.win_multiplier_distributions.iter()
            .find(|d| d.feature_name.eq_ignore_ascii_case(name))
    }

    /// Validate PAR+ data consistency
    pub fn validate(&self) -> Vec<ParPlusWarning> {
        let mut warnings = Vec::new();

        // Check win distributions are normalized
        for dist in &self.win_multiplier_distributions {
            if !dist.is_normalized() {
                let sum: f64 = dist.buckets.iter().map(|b| b.probability).sum();
                warnings.push(ParPlusWarning {
                    field: format!("win_multiplier_distributions.{}.buckets", dist.feature_name),
                    message: format!(
                        "Bucket probabilities sum to {:.4} (expected 1.0)",
                        sum
                    ),
                });
            }
        }

        // Check near-miss compliance
        if !self.near_miss_rates.passes_mga_ratio_check() {
            warnings.push(ParPlusWarning {
                field: "near_miss_rates.near_miss_to_trigger_ratio".to_string(),
                message: format!(
                    "Near-miss ratio {:.1} exceeds MGA limit of 12.0",
                    self.near_miss_rates.near_miss_to_trigger_ratio
                ),
            });
        }

        // Check session loss streak
        if !self.session_volatility.passes_ukgc_loss_streak() {
            warnings.push(ParPlusWarning {
                field: "session_volatility.consecutive_loss_p99".to_string(),
                message: format!(
                    "99th percentile consecutive loss streak {} exceeds UKGC limit of 200",
                    self.session_volatility.consecutive_loss_p99
                ),
            });
        }

        warnings
    }
}

/// A PAR+ validation warning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParPlusWarning {
    pub field: String,
    pub message: String,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAR+ DOCUMENT (PAR + PAR+)
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete PAR+ document — standard PAR with extension block
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParPlusDocument {
    // Re-embed ParDocument fields via flattening
    #[serde(flatten)]
    pub par: super::par::ParDocument,

    /// PAR+ extension (optional — absent = standard PAR)
    #[serde(default)]
    pub par_plus: Option<ParPlusExtension>,
}

impl ParPlusDocument {
    /// Does this document have PAR+ data?
    pub fn has_plus(&self) -> bool {
        self.par_plus.is_some()
    }

    /// Get PAR+ extension (empty default if absent)
    pub fn plus(&self) -> &ParPlusExtension {
        static DEFAULT: std::sync::OnceLock<ParPlusExtension> = std::sync::OnceLock::new();
        self.par_plus.as_ref().unwrap_or_else(|| {
            DEFAULT.get_or_init(ParPlusExtension::default)
        })
    }

    /// Validate the full PAR+ document
    pub fn validate_plus(&self) -> Vec<ParPlusWarning> {
        match &self.par_plus {
            Some(ext) => ext.validate(),
            None => vec![],
        }
    }
}

/// PAR+ parse errors
#[derive(Debug, thiserror::Error)]
pub enum ParPlusParseError {
    #[error("JSON error: {0}")]
    Json(String),
    #[error("PAR base error: {0}")]
    ParBase(String),
    #[error("Invalid PAR+ version: {0} (expected 1.0)")]
    VersionMismatch(String),
}

/// PAR+ parser — extends the standard ParParser
pub struct ParPlusParser;

impl ParPlusParser {
    /// Parse a PAR+ JSON document (superset of standard PAR)
    pub fn parse_json(json: &str) -> Result<ParPlusDocument, ParPlusParseError> {
        serde_json::from_str(json).map_err(|e| ParPlusParseError::Json(e.to_string()))
    }

    /// Parse and validate in one step
    pub fn parse_and_validate(json: &str) -> Result<(ParPlusDocument, Vec<ParPlusWarning>), ParPlusParseError> {
        let doc = Self::parse_json(json)?;
        let warnings = doc.validate_plus();
        Ok((doc, warnings))
    }

    /// Generate a PAR+ template JSON from scratch (for new document authoring)
    pub fn generate_template(game_name: &str, game_id: &str, rtp: f64) -> String {
        serde_json::json!({
            "game_name": game_name,
            "game_id": game_id,
            "rtp_target": rtp,
            "volatility": "MEDIUM",
            "reels": 5,
            "rows": 3,
            "paylines": 20,
            "hit_frequency": 0.32,
            "dead_spin_frequency": 0.68,
            "rtp_breakdown": {
                "base_game_rtp": 72.5,
                "free_spins_rtp": 24.0,
                "bonus_rtp": 0.0,
                "jackpot_rtp": 0.0,
                "gamble_rtp": 0.0,
                "total_rtp": rtp
            },
            "features": [
                {
                    "feature_type": "FREE_SPINS",
                    "name": "Free Spins",
                    "trigger_probability": 0.0067,
                    "avg_payout_multiplier": 35.8,
                    "rtp_contribution": 0.24,
                    "avg_duration_spins": 12.5,
                    "retrigger_probability": 0.073
                }
            ],
            "par_plus": {
                "version": "1.0",
                "feature_trigger_matrices": [
                    {
                        "feature_name": "Free Spins",
                        "scatter_count_probs": {
                            "3": 0.0067,
                            "4": 0.0009,
                            "5": 0.0001
                        },
                        "per_reel_probs": [0.22, 0.21, 0.19, 0.21, 0.20],
                        "retrigger_probability": 0.073,
                        "avg_duration_spins": 12.5,
                        "win_multiplier": 1.0,
                        "avg_total_multiplier": 35.8
                    }
                ],
                "win_multiplier_distributions": [
                    {
                        "feature_name": "Free Spins",
                        "buckets": [
                            {"from_multiplier": 0.0, "to_multiplier": 10.0, "probability": 0.45},
                            {"from_multiplier": 10.0, "to_multiplier": 50.0, "probability": 0.35},
                            {"from_multiplier": 50.0, "to_multiplier": 200.0, "probability": 0.15},
                            {"from_multiplier": 200.0, "to_multiplier": 10000.0, "probability": 0.05}
                        ],
                        "mean": 35.8,
                        "std_dev": 28.2,
                        "p95": 120.0,
                        "p99": 280.0,
                        "max_observed": 4800.0
                    }
                ],
                "session_volatility": {
                    "rtp_std_dev": 12.5,
                    "session_rtp_p10": 75.0,
                    "session_rtp_p50": rtp,
                    "session_rtp_p90": 118.0,
                    "spins_per_bonus_avg": 149.0,
                    "consecutive_loss_p99": 47,
                    "theoretical_drain_100": 3.5
                },
                "near_miss_rates": {
                    "rates": {
                        "two_scatter": 0.043,
                        "two_wild_expanding": 0.028
                    },
                    "near_miss_to_trigger_ratio": 6.4,
                    "mathematically_fair": true
                }
            }
        }).to_string()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_par_plus_json() -> String {
        ParPlusParser::generate_template("Golden Pantheon", "golden_pantheon_v2", 96.5)
    }

    #[test]
    fn test_parse_par_plus_json() {
        let json = sample_par_plus_json();
        let doc = ParPlusParser::parse_json(&json).unwrap();
        assert_eq!(doc.par.game_name, "Golden Pantheon");
        assert!(doc.has_plus());
    }

    #[test]
    fn test_par_plus_trigger_matrix_lookup() {
        let json = sample_par_plus_json();
        let doc = ParPlusParser::parse_json(&json).unwrap();
        let ext = doc.par_plus.as_ref().unwrap();

        let matrix = ext.trigger_matrix("Free Spins");
        assert!(matrix.is_some());
        let m = matrix.unwrap();
        assert!((m.retrigger_probability - 0.073).abs() < 0.001);
        assert_eq!(m.per_reel_probs.len(), 5);
    }

    #[test]
    fn test_par_plus_win_distribution_normalized() {
        let json = sample_par_plus_json();
        let doc = ParPlusParser::parse_json(&json).unwrap();
        let ext = doc.par_plus.as_ref().unwrap();

        let dist = ext.win_distribution("Free Spins").unwrap();
        assert!(dist.is_normalized(), "Bucket probs should sum to 1.0");
    }

    #[test]
    fn test_par_plus_prob_exceeding() {
        let json = sample_par_plus_json();
        let doc = ParPlusParser::parse_json(&json).unwrap();
        let ext = doc.par_plus.as_ref().unwrap();

        let dist = ext.win_distribution("Free Spins").unwrap();
        let prob_200x = dist.prob_exceeding(200.0);
        assert!((prob_200x - 0.05).abs() < 0.001);
    }

    #[test]
    fn test_near_miss_mga_compliance() {
        let rates = NearMissRates {
            near_miss_to_trigger_ratio: 6.4,
            mathematically_fair: true,
            ..Default::default()
        };
        assert!(rates.passes_mga_ratio_check());

        let bad = NearMissRates {
            near_miss_to_trigger_ratio: 15.0,
            ..Default::default()
        };
        assert!(!bad.passes_mga_ratio_check());
    }

    #[test]
    fn test_ukgc_loss_streak() {
        let metrics = SessionVolatilityMetrics {
            consecutive_loss_p99: 47,
            ..Default::default()
        };
        assert!(metrics.passes_ukgc_loss_streak());

        let bad = SessionVolatilityMetrics {
            consecutive_loss_p99: 250,
            ..Default::default()
        };
        assert!(!bad.passes_ukgc_loss_streak());
    }

    #[test]
    fn test_par_plus_validate_warnings() {
        let json = sample_par_plus_json();
        let (doc, warnings) = ParPlusParser::parse_and_validate(&json).unwrap();
        assert!(doc.has_plus());
        // Template data is valid — expect no warnings
        assert!(
            warnings.is_empty(),
            "Unexpected warnings: {:?}", warnings
        );
    }

    #[test]
    fn test_par_plus_absent_returns_default() {
        // Standard PAR JSON without par_plus block
        let json = r#"{
            "game_name": "Basic Slot",
            "game_id": "basic_001",
            "rtp_target": 95.0,
            "volatility": "MEDIUM",
            "reels": 5,
            "rows": 3
        }"#;
        let doc = ParPlusParser::parse_json(json).unwrap();
        assert!(!doc.has_plus());
        let ext = doc.plus();
        assert!(ext.feature_trigger_matrices.is_empty());
    }

    #[test]
    fn test_scatter_count_probabilities() {
        let json = sample_par_plus_json();
        let doc = ParPlusParser::parse_json(&json).unwrap();
        let matrix = doc.plus().trigger_matrix("Free Spins").unwrap();

        // sum of scatter count probs
        let total = matrix.expected_trigger_rate();
        assert!((total - 0.0077).abs() < 0.001, "total={total}");
    }
}
