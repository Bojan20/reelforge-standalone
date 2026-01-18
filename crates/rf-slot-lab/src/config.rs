//! Slot engine configuration

use serde::{Deserialize, Serialize};

/// Grid specification (reels × rows)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct GridSpec {
    /// Number of reels (columns)
    pub reels: u8,
    /// Number of visible rows per reel
    pub rows: u8,
    /// Total paylines (0 = ways-to-win)
    pub paylines: u16,
}

impl GridSpec {
    /// Standard 5×3 with 20 paylines
    pub fn standard_5x3() -> Self {
        Self {
            reels: 5,
            rows: 3,
            paylines: 20,
        }
    }

    /// Standard 5×4 with 40 paylines
    pub fn standard_5x4() -> Self {
        Self {
            reels: 5,
            rows: 4,
            paylines: 40,
        }
    }

    /// 6×4 Megaways-style (ways calculated dynamically)
    pub fn megaways_6x4() -> Self {
        Self {
            reels: 6,
            rows: 4,
            paylines: 0, // Ways-to-win
        }
    }

    /// Total grid positions
    pub fn total_positions(&self) -> usize {
        self.reels as usize * self.rows as usize
    }

    /// Is this a ways-to-win game?
    pub fn is_ways(&self) -> bool {
        self.paylines == 0
    }
}

impl Default for GridSpec {
    fn default() -> Self {
        Self::standard_5x3()
    }
}

/// Volatility profile controlling win distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolatilityProfile {
    /// Name for reference
    pub name: String,

    /// Base hit rate (% of spins that win something)
    /// Low vol: 35-40%, Medium: 25-30%, High: 15-20%
    pub hit_rate: f64,

    /// Big win frequency (% of wins that are big wins)
    pub big_win_frequency: f64,

    /// Feature trigger frequency (% of spins that trigger features)
    pub feature_frequency: f64,

    /// Jackpot trigger frequency (per spin, usually very low)
    pub jackpot_frequency: f64,

    /// Near miss frequency (for anticipation audio)
    pub near_miss_frequency: f64,

    /// Cascade probability (if cascades enabled)
    pub cascade_probability: f64,

    /// Win tier thresholds (bet multipliers)
    pub win_tier_thresholds: WinTierThresholds,
}

/// Thresholds for categorizing wins
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierThresholds {
    /// Minimum ratio for "big win"
    pub big_win: f64,
    /// Minimum ratio for "mega win"
    pub mega_win: f64,
    /// Minimum ratio for "epic win"
    pub epic_win: f64,
    /// Minimum ratio for "ultra win"
    pub ultra_win: f64,
}

impl Default for WinTierThresholds {
    fn default() -> Self {
        Self {
            big_win: 15.0,
            mega_win: 25.0,
            epic_win: 50.0,
            ultra_win: 100.0,
        }
    }
}

impl VolatilityProfile {
    /// Low volatility - frequent small wins
    pub fn low() -> Self {
        Self {
            name: "Low".into(),
            hit_rate: 0.38,
            big_win_frequency: 0.02,
            feature_frequency: 0.012,
            jackpot_frequency: 0.0001,
            near_miss_frequency: 0.15,
            cascade_probability: 0.25,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Medium volatility - balanced
    pub fn medium() -> Self {
        Self {
            name: "Medium".into(),
            hit_rate: 0.28,
            big_win_frequency: 0.05,
            feature_frequency: 0.008,
            jackpot_frequency: 0.00005,
            near_miss_frequency: 0.20,
            cascade_probability: 0.30,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// High volatility - rare big wins
    pub fn high() -> Self {
        Self {
            name: "High".into(),
            hit_rate: 0.18,
            big_win_frequency: 0.10,
            feature_frequency: 0.005,
            jackpot_frequency: 0.00002,
            near_miss_frequency: 0.25,
            cascade_probability: 0.35,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Studio mode - high frequency for testing
    pub fn studio() -> Self {
        Self {
            name: "Studio".into(),
            hit_rate: 0.60,
            big_win_frequency: 0.20,
            feature_frequency: 0.10,
            jackpot_frequency: 0.01,
            near_miss_frequency: 0.30,
            cascade_probability: 0.50,
            win_tier_thresholds: WinTierThresholds::default(),
        }
    }

    /// Interpolate between two profiles
    pub fn interpolate(low: &Self, high: &Self, t: f64) -> Self {
        let t = t.clamp(0.0, 1.0);
        Self {
            name: format!("Custom ({:.0}%)", t * 100.0),
            hit_rate: low.hit_rate + (high.hit_rate - low.hit_rate) * t,
            big_win_frequency: low.big_win_frequency + (high.big_win_frequency - low.big_win_frequency) * t,
            feature_frequency: low.feature_frequency + (high.feature_frequency - low.feature_frequency) * t,
            jackpot_frequency: low.jackpot_frequency + (high.jackpot_frequency - low.jackpot_frequency) * t,
            near_miss_frequency: low.near_miss_frequency + (high.near_miss_frequency - low.near_miss_frequency) * t,
            cascade_probability: low.cascade_probability + (high.cascade_probability - low.cascade_probability) * t,
            win_tier_thresholds: low.win_tier_thresholds.clone(),
        }
    }
}

impl Default for VolatilityProfile {
    fn default() -> Self {
        Self::medium()
    }
}

/// Feature configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureConfig {
    /// Enable free spins feature
    pub free_spins_enabled: bool,
    /// Free spins count range (min, max)
    pub free_spins_range: (u32, u32),
    /// Multiplier during free spins
    pub free_spins_multiplier: f64,

    /// Enable cascades/tumbles
    pub cascades_enabled: bool,
    /// Max cascade steps
    pub max_cascade_steps: u32,
    /// Cascade multiplier progression (per step)
    pub cascade_multiplier_step: f64,

    /// Enable hold-and-spin
    pub hold_spin_enabled: bool,
    /// Hold-and-spin respins
    pub hold_spin_respins: u32,

    /// Enable gamble feature
    pub gamble_enabled: bool,
    /// Max gamble attempts per win
    pub max_gamble_attempts: u32,

    /// Jackpot tiers enabled
    pub jackpot_enabled: bool,
    /// Jackpot seed values (Mini, Minor, Major, Grand)
    pub jackpot_seeds: [f64; 4],
}

impl Default for FeatureConfig {
    fn default() -> Self {
        Self {
            free_spins_enabled: true,
            free_spins_range: (8, 15),
            free_spins_multiplier: 2.0,

            cascades_enabled: true,
            max_cascade_steps: 8,
            cascade_multiplier_step: 1.0,

            hold_spin_enabled: false,
            hold_spin_respins: 3,

            gamble_enabled: true,
            max_gamble_attempts: 5,

            jackpot_enabled: true,
            jackpot_seeds: [50.0, 200.0, 1000.0, 10000.0],
        }
    }
}

/// Complete slot configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotConfig {
    /// Game name
    pub name: String,
    /// Grid specification
    pub grid: GridSpec,
    /// Volatility profile
    pub volatility: VolatilityProfile,
    /// Feature configuration
    pub features: FeatureConfig,
    /// Default bet amount
    pub default_bet: f64,
    /// Available bet levels
    pub bet_levels: Vec<f64>,
    /// RTP target (for display, not enforced)
    pub target_rtp: f64,
}

impl Default for SlotConfig {
    fn default() -> Self {
        Self {
            name: "Synthetic Slot".into(),
            grid: GridSpec::default(),
            volatility: VolatilityProfile::default(),
            features: FeatureConfig::default(),
            default_bet: 1.0,
            bet_levels: vec![0.20, 0.50, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0],
            target_rtp: 96.5,
        }
    }
}

impl SlotConfig {
    /// Create config for audio testing (high event frequency)
    pub fn audio_test() -> Self {
        Self {
            name: "Audio Test Mode".into(),
            volatility: VolatilityProfile::studio(),
            features: FeatureConfig {
                free_spins_enabled: true,
                free_spins_range: (3, 5),
                cascades_enabled: true,
                max_cascade_steps: 3,
                ..Default::default()
            },
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grid_spec() {
        let grid = GridSpec::standard_5x3();
        assert_eq!(grid.total_positions(), 15);
        assert!(!grid.is_ways());

        let mega = GridSpec::megaways_6x4();
        assert!(mega.is_ways());
    }

    #[test]
    fn test_volatility_interpolate() {
        let low = VolatilityProfile::low();
        let high = VolatilityProfile::high();
        let mid = VolatilityProfile::interpolate(&low, &high, 0.5);

        assert!(mid.hit_rate > high.hit_rate);
        assert!(mid.hit_rate < low.hit_rate);
    }
}
