//! Win Tiers — Win categorization and thresholds

use serde::{Deserialize, Serialize};

/// Win tier configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTierConfig {
    /// Individual tier definitions
    pub tiers: Vec<WinTier>,

    /// Multiplier for "small win" display threshold
    /// Wins below this don't show special celebration
    #[serde(default = "default_display_threshold")]
    pub display_threshold: f64,
}

fn default_display_threshold() -> f64 {
    1.0 // Show celebration for wins >= 1x bet
}

impl WinTierConfig {
    /// Standard tier configuration
    pub fn standard() -> Self {
        Self {
            tiers: vec![
                WinTier::new("small", 1.0, 5.0),
                WinTier::new("medium", 5.0, 15.0),
                WinTier::new("big", 15.0, 25.0),
                WinTier::new("mega", 25.0, 50.0),
                WinTier::new("epic", 50.0, 100.0),
                WinTier::new("ultra", 100.0, f64::INFINITY),
            ],
            display_threshold: 1.0,
        }
    }

    /// High volatility tiers (higher thresholds)
    pub fn high_volatility() -> Self {
        Self {
            tiers: vec![
                WinTier::new("small", 1.0, 10.0),
                WinTier::new("medium", 10.0, 25.0),
                WinTier::new("big", 25.0, 50.0),
                WinTier::new("mega", 50.0, 100.0),
                WinTier::new("epic", 100.0, 250.0),
                WinTier::new("ultra", 250.0, f64::INFINITY),
            ],
            display_threshold: 2.0,
        }
    }

    /// Get tier for a given win ratio (win / bet)
    pub fn get_tier(&self, win_ratio: f64) -> Option<&WinTier> {
        self.tiers
            .iter()
            .find(|t| win_ratio >= t.min_ratio && win_ratio < t.max_ratio)
    }

    /// Get tier name for a given win ratio
    pub fn get_tier_name(&self, win_ratio: f64) -> Option<&str> {
        self.get_tier(win_ratio).map(|t| t.name.as_str())
    }

    /// Check if win ratio should show celebration
    pub fn should_celebrate(&self, win_ratio: f64) -> bool {
        win_ratio >= self.display_threshold
    }

    /// Get all tier names in order
    pub fn tier_names(&self) -> Vec<&str> {
        self.tiers.iter().map(|t| t.name.as_str()).collect()
    }
}

impl Default for WinTierConfig {
    fn default() -> Self {
        Self::standard()
    }
}

/// A single win tier definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinTier {
    /// Tier name (e.g., "big", "mega", "epic")
    pub name: String,

    /// Minimum win ratio (inclusive)
    pub min_ratio: f64,

    /// Maximum win ratio (exclusive)
    pub max_ratio: f64,

    /// Celebration duration multiplier
    #[serde(default = "default_celebration_mult")]
    pub celebration_duration_mult: f64,

    /// Audio event suffix (e.g., "_big", "_mega")
    #[serde(default)]
    pub audio_suffix: Option<String>,

    /// Visual effect intensity (0.0 - 1.0)
    #[serde(default = "default_effect_intensity")]
    pub effect_intensity: f64,
}

fn default_celebration_mult() -> f64 {
    1.0
}

fn default_effect_intensity() -> f64 {
    0.5
}

impl WinTier {
    /// Create a new win tier
    pub fn new(name: impl Into<String>, min_ratio: f64, max_ratio: f64) -> Self {
        let name = name.into();
        let celebration_mult = match name.as_str() {
            "small" => 1.0,
            "medium" => 1.2,
            "big" => 1.5,
            "mega" => 2.0,
            "epic" => 2.5,
            "ultra" => 3.0,
            _ => 1.0,
        };
        let effect_intensity = match name.as_str() {
            "small" => 0.2,
            "medium" => 0.4,
            "big" => 0.6,
            "mega" => 0.8,
            "epic" => 0.9,
            "ultra" => 1.0,
            _ => 0.5,
        };

        Self {
            audio_suffix: Some(format!("_{}", name)),
            name,
            min_ratio,
            max_ratio,
            celebration_duration_mult: celebration_mult,
            effect_intensity,
        }
    }

    /// Check if a win ratio falls in this tier
    pub fn contains(&self, win_ratio: f64) -> bool {
        win_ratio >= self.min_ratio && win_ratio < self.max_ratio
    }

    /// Get the center point of this tier (for testing)
    pub fn center_ratio(&self) -> f64 {
        if self.max_ratio.is_infinite() {
            self.min_ratio * 1.5
        } else {
            (self.min_ratio + self.max_ratio) / 2.0
        }
    }
}

/// Predefined win tier enum for quick matching
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WinTierType {
    Small,
    Medium,
    Big,
    Mega,
    Epic,
    Ultra,
}

impl WinTierType {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Small => "Small Win",
            Self::Medium => "Medium Win",
            Self::Big => "Big Win",
            Self::Mega => "Mega Win",
            Self::Epic => "Epic Win",
            Self::Ultra => "Ultra Win",
        }
    }

    /// Get from win ratio using standard thresholds
    pub fn from_ratio(ratio: f64) -> Option<Self> {
        match ratio {
            r if r >= 100.0 => Some(Self::Ultra),
            r if r >= 50.0 => Some(Self::Epic),
            r if r >= 25.0 => Some(Self::Mega),
            r if r >= 15.0 => Some(Self::Big),
            r if r >= 5.0 => Some(Self::Medium),
            r if r >= 1.0 => Some(Self::Small),
            _ => None,
        }
    }

    /// Get tier index (for ordering)
    pub fn index(&self) -> u8 {
        match self {
            Self::Small => 0,
            Self::Medium => 1,
            Self::Big => 2,
            Self::Mega => 3,
            Self::Epic => 4,
            Self::Ultra => 5,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_win_tier_config() {
        let config = WinTierConfig::standard();

        assert_eq!(config.get_tier_name(2.0), Some("small"));
        assert_eq!(config.get_tier_name(10.0), Some("medium"));
        assert_eq!(config.get_tier_name(20.0), Some("big"));
        assert_eq!(config.get_tier_name(30.0), Some("mega"));
        assert_eq!(config.get_tier_name(75.0), Some("epic"));
        assert_eq!(config.get_tier_name(150.0), Some("ultra"));
        assert_eq!(config.get_tier_name(0.5), None);
    }

    #[test]
    fn test_win_tier_contains() {
        let tier = WinTier::new("big", 15.0, 25.0);

        assert!(!tier.contains(14.9));
        assert!(tier.contains(15.0));
        assert!(tier.contains(20.0));
        assert!(!tier.contains(25.0));
    }

    #[test]
    fn test_win_tier_type() {
        assert_eq!(WinTierType::from_ratio(150.0), Some(WinTierType::Ultra));
        assert_eq!(WinTierType::from_ratio(20.0), Some(WinTierType::Big));
        assert_eq!(WinTierType::from_ratio(0.5), None);
    }

    #[test]
    fn test_celebration() {
        let config = WinTierConfig::standard();

        assert!(config.should_celebrate(1.0));
        assert!(config.should_celebrate(50.0));
        assert!(!config.should_celebrate(0.5));
    }
}
