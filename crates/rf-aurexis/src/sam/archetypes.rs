//! SAM: Slot Archetypes
//!
//! 8 game archetypes with default parameter profiles.
//! Maps to existing SlotProfile for energy governance.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §13

use crate::energy::SlotProfile;

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// 8 SAM archetypes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SlotArchetype {
    Classic3Reel,
    HoldAndWin,
    CascadeHeavy,
    MegawaysStyle,
    ClusterPay,
    JackpotHeavy,
    FeatureStorm,
    TurboArcade,
}

impl SlotArchetype {
    pub const COUNT: usize = 8;

    pub fn all() -> &'static [SlotArchetype; 8] {
        &[
            Self::Classic3Reel,
            Self::HoldAndWin,
            Self::CascadeHeavy,
            Self::MegawaysStyle,
            Self::ClusterPay,
            Self::JackpotHeavy,
            Self::FeatureStorm,
            Self::TurboArcade,
        ]
    }

    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::Classic3Reel),
            1 => Some(Self::HoldAndWin),
            2 => Some(Self::CascadeHeavy),
            3 => Some(Self::MegawaysStyle),
            4 => Some(Self::ClusterPay),
            5 => Some(Self::JackpotHeavy),
            6 => Some(Self::FeatureStorm),
            7 => Some(Self::TurboArcade),
            _ => None,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Classic3Reel  => "Classic 3-Reel",
            Self::HoldAndWin    => "Hold & Win",
            Self::CascadeHeavy  => "Cascade Heavy",
            Self::MegawaysStyle => "Megaways Style",
            Self::ClusterPay    => "Cluster Pay",
            Self::JackpotHeavy  => "Jackpot Heavy",
            Self::FeatureStorm  => "Feature Storm",
            Self::TurboArcade   => "Turbo Arcade",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Classic3Reel  => "Traditional 3-reel slot with simple mechanics",
            Self::HoldAndWin    => "Hold mechanics with respins and collect features",
            Self::CascadeHeavy  => "Cascading/avalanche reels with chain multipliers",
            Self::MegawaysStyle => "Dynamic reel sizes with high ways-to-win",
            Self::ClusterPay    => "Cluster-based wins on grid layout",
            Self::JackpotHeavy  => "Jackpot-focused with progressive tiers",
            Self::FeatureStorm  => "Feature-rich with frequent bonus triggers",
            Self::TurboArcade   => "Fast-paced arcade-style gameplay",
        }
    }

    /// Map to corresponding energy governance SlotProfile.
    pub fn slot_profile(&self) -> SlotProfile {
        match self {
            Self::Classic3Reel  => SlotProfile::Classic3Reel,
            Self::HoldAndWin    => SlotProfile::MediumVolatility,
            Self::CascadeHeavy  => SlotProfile::CascadeHeavy,
            Self::MegawaysStyle => SlotProfile::MegawaysStyle,
            Self::ClusterPay    => SlotProfile::ClusterPay,
            Self::JackpotHeavy  => SlotProfile::JackpotFocused,
            Self::FeatureStorm  => SlotProfile::FeatureHeavy,
            Self::TurboArcade   => SlotProfile::HighVolatility,
        }
    }

    /// Get default profile for this archetype.
    pub fn defaults(&self) -> ArchetypeDefaults {
        match self {
            Self::Classic3Reel => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.1, max: 0.4, default: 0.25 },
                market: MarketTarget::Casual,
                intensity: 0.3,
                build_speed: 0.2,
                peak_aggression: 0.3,
                decay_rate: 0.5,
                mix_tightness: 0.7,
                transient_sharpness: 0.4,
                width: 0.4,
                harmonics: 0.3,
                fatigue_target: 0.3,
                peak_duration_target: 0.3,
                voice_density_target: 0.3,
                voice_budget: 16,
                typical_rtp: 96.0,
            },
            Self::HoldAndWin => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.3, max: 0.7, default: 0.5 },
                market: MarketTarget::Standard,
                intensity: 0.5,
                build_speed: 0.4,
                peak_aggression: 0.5,
                decay_rate: 0.4,
                mix_tightness: 0.6,
                transient_sharpness: 0.5,
                width: 0.5,
                harmonics: 0.4,
                fatigue_target: 0.5,
                peak_duration_target: 0.5,
                voice_density_target: 0.5,
                voice_budget: 32,
                typical_rtp: 96.5,
            },
            Self::CascadeHeavy => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.4, max: 0.8, default: 0.6 },
                market: MarketTarget::Standard,
                intensity: 0.7,
                build_speed: 0.7,
                peak_aggression: 0.6,
                decay_rate: 0.3,
                mix_tightness: 0.5,
                transient_sharpness: 0.7,
                width: 0.6,
                harmonics: 0.6,
                fatigue_target: 0.6,
                peak_duration_target: 0.6,
                voice_density_target: 0.7,
                voice_budget: 48,
                typical_rtp: 96.0,
            },
            Self::MegawaysStyle => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.5, max: 0.9, default: 0.7 },
                market: MarketTarget::Standard,
                intensity: 0.8,
                build_speed: 0.6,
                peak_aggression: 0.8,
                decay_rate: 0.3,
                mix_tightness: 0.5,
                transient_sharpness: 0.6,
                width: 0.7,
                harmonics: 0.7,
                fatigue_target: 0.7,
                peak_duration_target: 0.7,
                voice_density_target: 0.8,
                voice_budget: 48,
                typical_rtp: 96.0,
            },
            Self::ClusterPay => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.3, max: 0.7, default: 0.5 },
                market: MarketTarget::Standard,
                intensity: 0.6,
                build_speed: 0.5,
                peak_aggression: 0.5,
                decay_rate: 0.4,
                mix_tightness: 0.6,
                transient_sharpness: 0.5,
                width: 0.6,
                harmonics: 0.5,
                fatigue_target: 0.5,
                peak_duration_target: 0.5,
                voice_density_target: 0.6,
                voice_budget: 32,
                typical_rtp: 96.5,
            },
            Self::JackpotHeavy => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.6, max: 0.95, default: 0.8 },
                market: MarketTarget::Premium,
                intensity: 0.9,
                build_speed: 0.3,
                peak_aggression: 0.9,
                decay_rate: 0.2,
                mix_tightness: 0.4,
                transient_sharpness: 0.8,
                width: 0.7,
                harmonics: 0.8,
                fatigue_target: 0.7,
                peak_duration_target: 0.8,
                voice_density_target: 0.8,
                voice_budget: 48,
                typical_rtp: 95.5,
            },
            Self::FeatureStorm => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.5, max: 0.85, default: 0.65 },
                market: MarketTarget::Standard,
                intensity: 0.7,
                build_speed: 0.8,
                peak_aggression: 0.7,
                decay_rate: 0.3,
                mix_tightness: 0.5,
                transient_sharpness: 0.6,
                width: 0.7,
                harmonics: 0.7,
                fatigue_target: 0.7,
                peak_duration_target: 0.7,
                voice_density_target: 0.8,
                voice_budget: 48,
                typical_rtp: 96.0,
            },
            Self::TurboArcade => ArchetypeDefaults {
                archetype: *self,
                volatility: VolatilityRange { min: 0.6, max: 0.95, default: 0.8 },
                market: MarketTarget::Premium,
                intensity: 0.9,
                build_speed: 0.9,
                peak_aggression: 0.8,
                decay_rate: 0.4,
                mix_tightness: 0.4,
                transient_sharpness: 0.8,
                width: 0.8,
                harmonics: 0.7,
                fatigue_target: 0.8,
                peak_duration_target: 0.8,
                voice_density_target: 0.9,
                voice_budget: 64,
                typical_rtp: 96.0,
            },
        }
    }
}

/// Volatility range for an archetype.
#[derive(Debug, Clone, Copy)]
pub struct VolatilityRange {
    pub min: f64,
    pub max: f64,
    pub default: f64,
}

/// Target market segment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MarketTarget {
    Casual,
    Standard,
    Premium,
}

impl MarketTarget {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Casual   => "Casual",
            Self::Standard => "Standard",
            Self::Premium  => "Premium",
        }
    }

    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(Self::Casual),
            1 => Some(Self::Standard),
            2 => Some(Self::Premium),
            _ => None,
        }
    }
}

/// Full default configuration for an archetype.
#[derive(Debug, Clone)]
pub struct ArchetypeDefaults {
    pub archetype: SlotArchetype,
    pub volatility: VolatilityRange,
    pub market: MarketTarget,

    // Energy controls
    pub intensity: f64,
    pub build_speed: f64,
    pub peak_aggression: f64,
    pub decay_rate: f64,

    // Clarity controls
    pub mix_tightness: f64,
    pub transient_sharpness: f64,
    pub width: f64,
    pub harmonics: f64,

    // Stability controls
    pub fatigue_target: f64,
    pub peak_duration_target: f64,
    pub voice_density_target: f64,

    // Engine params
    pub voice_budget: u32,
    pub typical_rtp: f64,
}

/// Archetype profile (for serialization/display).
#[derive(Debug, Clone)]
pub struct ArchetypeProfile {
    pub archetype: SlotArchetype,
    pub name: &'static str,
    pub description: &'static str,
    pub defaults: ArchetypeDefaults,
}

impl ArchetypeProfile {
    pub fn from_archetype(archetype: SlotArchetype) -> Self {
        Self {
            archetype,
            name: archetype.name(),
            description: archetype.description(),
            defaults: archetype.defaults(),
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_archetypes() {
        let all = SlotArchetype::all();
        assert_eq!(all.len(), 8);
    }

    #[test]
    fn test_archetype_from_index() {
        for i in 0..8 {
            assert!(SlotArchetype::from_index(i).is_some());
        }
        assert!(SlotArchetype::from_index(8).is_none());
    }

    #[test]
    fn test_archetype_slot_profile_mapping() {
        for arch in SlotArchetype::all() {
            let _profile = arch.slot_profile();
            // Just ensure no panic — mapping is valid
        }
    }

    #[test]
    fn test_archetype_defaults_valid() {
        for arch in SlotArchetype::all() {
            let d = arch.defaults();
            assert!(d.volatility.min < d.volatility.max);
            assert!(d.volatility.default >= d.volatility.min);
            assert!(d.volatility.default <= d.volatility.max);
            assert!(d.intensity >= 0.0 && d.intensity <= 1.0);
            assert!(d.voice_budget > 0 && d.voice_budget <= 64);
            assert!(d.typical_rtp >= 85.0 && d.typical_rtp <= 99.5);
        }
    }

    #[test]
    fn test_market_from_index() {
        assert_eq!(MarketTarget::from_index(0), Some(MarketTarget::Casual));
        assert_eq!(MarketTarget::from_index(1), Some(MarketTarget::Standard));
        assert_eq!(MarketTarget::from_index(2), Some(MarketTarget::Premium));
        assert_eq!(MarketTarget::from_index(3), None);
    }
}
