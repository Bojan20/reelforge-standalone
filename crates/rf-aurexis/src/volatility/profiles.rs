use crate::core::config::VolatilityConfig;
use serde::{Deserialize, Serialize};

/// Named volatility preset with associated config overrides.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolatilityProfile {
    pub name: String,
    pub description: String,
    /// Recommended volatility index range (min, max).
    pub volatility_range: (f64, f64),
    /// Config overrides for this profile.
    pub config: VolatilityConfig,
}

impl VolatilityProfile {
    /// Low volatility: gentle transitions, narrow stereo, low energy.
    pub fn low() -> Self {
        Self {
            name: "Low".into(),
            description: "Classic slots, gentle transitions, focused audio".into(),
            volatility_range: (0.0, 0.3),
            config: VolatilityConfig {
                elasticity_min: 0.2,
                elasticity_max: 0.8,
                elasticity_curve_exp: 1.0,
                energy_density_min: 0.1,
                energy_density_max: 0.5,
                escalation_rate_max: 1.3,
                micro_dynamics_max: 0.3,
            },
        }
    }

    /// Medium volatility: balanced, standard video slot.
    pub fn medium() -> Self {
        Self {
            name: "Medium".into(),
            description: "Standard video slots, balanced dynamics".into(),
            volatility_range: (0.3, 0.6),
            config: VolatilityConfig::default(),
        }
    }

    /// High volatility: aggressive stereo, fast escalation.
    pub fn high() -> Self {
        Self {
            name: "High".into(),
            description: "High volatility, wide stereo, aggressive escalation".into(),
            volatility_range: (0.6, 0.85),
            config: VolatilityConfig {
                elasticity_min: 0.4,
                elasticity_max: 2.0,
                elasticity_curve_exp: 1.8,
                energy_density_min: 0.3,
                energy_density_max: 0.95,
                escalation_rate_max: 2.5,
                micro_dynamics_max: 0.9,
            },
        }
    }

    /// Extreme volatility: maximum dynamics, megaways-level chaos.
    pub fn extreme() -> Self {
        Self {
            name: "Extreme".into(),
            description: "Megaways, maximum variation, instant transitions".into(),
            volatility_range: (0.85, 1.0),
            config: VolatilityConfig {
                elasticity_min: 0.5,
                elasticity_max: 2.5,
                elasticity_curve_exp: 2.0,
                energy_density_min: 0.4,
                energy_density_max: 1.0,
                escalation_rate_max: 3.0,
                micro_dynamics_max: 1.0,
            },
        }
    }

    /// Get all built-in profiles.
    pub fn all_presets() -> Vec<Self> {
        vec![Self::low(), Self::medium(), Self::high(), Self::extreme()]
    }

    /// Select the best matching profile for a given volatility index.
    pub fn select_for_volatility(volatility: f64) -> Self {
        if volatility < 0.3 {
            Self::low()
        } else if volatility < 0.6 {
            Self::medium()
        } else if volatility < 0.85 {
            Self::high()
        } else {
            Self::extreme()
        }
    }
}
