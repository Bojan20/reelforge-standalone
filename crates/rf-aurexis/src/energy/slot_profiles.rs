//! GEG-2: Slot Profiles — 9 game archetypes with per-domain energy multipliers.

use serde::{Deserialize, Serialize};

/// 9 slot game archetypes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SlotProfile {
    HighVolatility,
    MediumVolatility,
    LowVolatility,
    CascadeHeavy,
    FeatureHeavy,
    JackpotFocused,
    Classic3Reel,
    ClusterPay,
    MegawaysStyle,
}

impl SlotProfile {
    /// Get profile data for this slot profile.
    pub fn data(&self) -> &'static SlotProfileData {
        &SLOT_PROFILES[*self as usize]
    }

    /// All 9 profiles.
    pub fn all() -> &'static [SlotProfile; 9] {
        &[
            SlotProfile::HighVolatility,
            SlotProfile::MediumVolatility,
            SlotProfile::LowVolatility,
            SlotProfile::CascadeHeavy,
            SlotProfile::FeatureHeavy,
            SlotProfile::JackpotFocused,
            SlotProfile::Classic3Reel,
            SlotProfile::ClusterPay,
            SlotProfile::MegawaysStyle,
        ]
    }

    /// Display name.
    pub fn name(&self) -> &'static str {
        match self {
            SlotProfile::HighVolatility => "High Volatility",
            SlotProfile::MediumVolatility => "Medium Volatility",
            SlotProfile::LowVolatility => "Low Volatility",
            SlotProfile::CascadeHeavy => "Cascade Heavy",
            SlotProfile::FeatureHeavy => "Feature Heavy",
            SlotProfile::JackpotFocused => "Jackpot Focused",
            SlotProfile::Classic3Reel => "Classic 3-Reel",
            SlotProfile::ClusterPay => "Cluster Pay",
            SlotProfile::MegawaysStyle => "Megaways Style",
        }
    }
}

/// Per-domain energy multipliers for a slot profile.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotProfileData {
    pub profile: SlotProfile,
    /// SP multiplier for FinalCap formula.
    pub sp_multiplier: f64,
    /// Per-domain caps (Dynamic, Transient, Spatial, Harmonic, Temporal).
    pub domain_caps: [f64; 5],
    /// Default voice budget.
    pub voice_budget_max: u32,
    /// Default escalation curve.
    pub default_curve: super::GegCurveType,
}

/// Static profile data for all 9 archetypes.
pub static SLOT_PROFILES: [SlotProfileData; 9] = [
    // 0: HighVolatility — extreme peaks, wide dynamic range
    SlotProfileData {
        profile: SlotProfile::HighVolatility,
        sp_multiplier: 1.0,
        domain_caps: [1.0, 0.95, 0.9, 0.85, 0.8],
        voice_budget_max: 48,
        default_curve: super::GegCurveType::Exponential,
    },
    // 1: MediumVolatility — balanced
    SlotProfileData {
        profile: SlotProfile::MediumVolatility,
        sp_multiplier: 0.85,
        domain_caps: [0.85, 0.80, 0.80, 0.75, 0.75],
        voice_budget_max: 40,
        default_curve: super::GegCurveType::SCurve,
    },
    // 2: LowVolatility — frequent small wins, compressed dynamics
    SlotProfileData {
        profile: SlotProfile::LowVolatility,
        sp_multiplier: 0.70,
        domain_caps: [0.70, 0.65, 0.70, 0.65, 0.85],
        voice_budget_max: 32,
        default_curve: super::GegCurveType::Logarithmic,
    },
    // 3: CascadeHeavy — rapid temporal events, high transient density
    SlotProfileData {
        profile: SlotProfile::CascadeHeavy,
        sp_multiplier: 0.90,
        domain_caps: [0.80, 0.95, 0.75, 0.70, 0.95],
        voice_budget_max: 56,
        default_curve: super::GegCurveType::CappedExponential,
    },
    // 4: FeatureHeavy — rich harmonic layers, spatial variety
    SlotProfileData {
        profile: SlotProfile::FeatureHeavy,
        sp_multiplier: 0.90,
        domain_caps: [0.85, 0.75, 0.90, 0.90, 0.80],
        voice_budget_max: 48,
        default_curve: super::GegCurveType::SCurve,
    },
    // 5: JackpotFocused — maximum peak energy, jackpot override
    SlotProfileData {
        profile: SlotProfile::JackpotFocused,
        sp_multiplier: 1.0,
        domain_caps: [1.0, 0.90, 0.85, 0.80, 0.70],
        voice_budget_max: 64,
        default_curve: super::GegCurveType::Exponential,
    },
    // 6: Classic3Reel — simple, low voice count, tight
    SlotProfileData {
        profile: SlotProfile::Classic3Reel,
        sp_multiplier: 0.65,
        domain_caps: [0.65, 0.60, 0.55, 0.50, 0.70],
        voice_budget_max: 24,
        default_curve: super::GegCurveType::Linear,
    },
    // 7: ClusterPay — spatial emphasis, clustered transients
    SlotProfileData {
        profile: SlotProfile::ClusterPay,
        sp_multiplier: 0.85,
        domain_caps: [0.80, 0.85, 0.90, 0.75, 0.80],
        voice_budget_max: 44,
        default_curve: super::GegCurveType::SCurve,
    },
    // 8: MegawaysStyle — high temporal density, many paylines
    SlotProfileData {
        profile: SlotProfile::MegawaysStyle,
        sp_multiplier: 0.95,
        domain_caps: [0.90, 0.90, 0.80, 0.85, 1.0],
        voice_budget_max: 56,
        default_curve: super::GegCurveType::CappedExponential,
    },
];
