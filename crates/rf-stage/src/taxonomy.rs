//! Stage Taxonomy — Enums for game elements
//!
//! These enums classify various game elements like big win tiers,
//! feature types, jackpot levels, etc.

use serde::{Deserialize, Serialize};

/// Big win tier classification
///
/// Standard tiers based on win-to-bet ratio:
/// - Win: 10-15x
/// - BigWin: 15-25x
/// - MegaWin: 25-50x
/// - EpicWin: 50-100x
/// - UltraWin: 100x+
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BigWinTier {
    Win,
    BigWin,
    MegaWin,
    EpicWin,
    UltraWin,
    /// Custom tier with numeric level (1-10)
    Custom(u8),
}

impl BigWinTier {
    /// Get tier from win-to-bet ratio
    pub fn from_ratio(ratio: f64) -> Self {
        match ratio {
            r if r >= 100.0 => Self::UltraWin,
            r if r >= 50.0 => Self::EpicWin,
            r if r >= 25.0 => Self::MegaWin,
            r if r >= 15.0 => Self::BigWin,
            _ => Self::Win,
        }
    }

    /// Get minimum ratio for this tier
    pub fn min_ratio(&self) -> f64 {
        match self {
            Self::Win => 10.0,
            Self::BigWin => 15.0,
            Self::MegaWin => 25.0,
            Self::EpicWin => 50.0,
            Self::UltraWin => 100.0,
            Self::Custom(_) => 0.0,
        }
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Win => "WIN",
            Self::BigWin => "BIG WIN",
            Self::MegaWin => "MEGA WIN",
            Self::EpicWin => "EPIC WIN",
            Self::UltraWin => "ULTRA WIN",
            Self::Custom(_) => "CUSTOM WIN",
        }
    }
}

/// Feature type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeatureType {
    /// Free spins bonus
    FreeSpins,
    /// Generic bonus game
    BonusGame,
    /// Pick-and-click bonus
    PickBonus,
    /// Wheel of fortune style
    WheelBonus,
    /// Single respin
    Respin,
    /// Hold and spin / Lock and spin
    HoldAndSpin,
    /// Expanding wilds feature
    ExpandingWilds,
    /// Sticky wilds feature
    StickyWilds,
    /// Multiplier feature
    Multiplier,
    /// Cascading/Tumbling reels
    Cascade,
    /// Mystery symbols
    MysterySymbols,
    /// Walking wilds
    WalkingWilds,
    /// Colossal reels
    ColossalReels,
    /// Megaways mechanic
    Megaways,
    /// Custom feature with ID
    Custom(u32),
}

impl FeatureType {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::FreeSpins => "Free Spins",
            Self::BonusGame => "Bonus Game",
            Self::PickBonus => "Pick Bonus",
            Self::WheelBonus => "Wheel Bonus",
            Self::Respin => "Respin",
            Self::HoldAndSpin => "Hold & Spin",
            Self::ExpandingWilds => "Expanding Wilds",
            Self::StickyWilds => "Sticky Wilds",
            Self::Multiplier => "Multiplier",
            Self::Cascade => "Cascade",
            Self::MysterySymbols => "Mystery Symbols",
            Self::WalkingWilds => "Walking Wilds",
            Self::ColossalReels => "Colossal Reels",
            Self::Megaways => "Megaways",
            Self::Custom(_) => "Custom Feature",
        }
    }

    /// Whether this feature typically has multiple steps
    pub fn is_multi_step(&self) -> bool {
        matches!(
            self,
            Self::FreeSpins
                | Self::HoldAndSpin
                | Self::Cascade
                | Self::WalkingWilds
                | Self::Custom(_)
        )
    }
}

/// Jackpot tier classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JackpotTier {
    Mini,
    Minor,
    Major,
    Grand,
    /// Custom tier with name ID
    Custom(u32),
}

impl JackpotTier {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Mini => "MINI",
            Self::Minor => "MINOR",
            Self::Major => "MAJOR",
            Self::Grand => "GRAND",
            Self::Custom(_) => "JACKPOT",
        }
    }

    /// Get tier level (for sorting)
    pub fn level(&self) -> u8 {
        match self {
            Self::Mini => 1,
            Self::Minor => 2,
            Self::Major => 3,
            Self::Grand => 4,
            Self::Custom(n) => 5 + (*n as u8),
        }
    }
}

/// Symbol position on reels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct SymbolPosition {
    /// Reel index (0-based)
    pub reel: u8,
    /// Row index (0-based, 0 = top)
    pub row: u8,
}

impl SymbolPosition {
    pub fn new(reel: u8, row: u8) -> Self {
        Self { reel, row }
    }
}

/// Win line definition
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WinLine {
    /// Line index
    pub line_index: u8,
    /// Positions that make up this win
    pub positions: Vec<SymbolPosition>,
    /// Symbol ID that won
    pub symbol_id: u32,
    /// Symbol name (optional)
    pub symbol_name: Option<String>,
    /// Number of matching symbols
    pub match_count: u8,
    /// Win amount for this line
    pub win_amount: f64,
    /// Multiplier applied
    pub multiplier: f64,
}

/// Gamble/Risk game result
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GambleResult {
    Win,
    Lose,
    Draw,
    Collected,
}

/// Bonus choice type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BonusChoiceType {
    /// Red/Black card guess
    RedBlack,
    /// Suit guess
    Suit,
    /// Higher/Lower
    HigherLower,
    /// Pick from options
    Pick,
    /// Wheel spin
    Wheel,
    /// Custom choice
    Custom(u32),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bigwin_tier_from_ratio() {
        assert_eq!(BigWinTier::from_ratio(5.0), BigWinTier::Win);
        assert_eq!(BigWinTier::from_ratio(20.0), BigWinTier::BigWin);
        assert_eq!(BigWinTier::from_ratio(30.0), BigWinTier::MegaWin);
        assert_eq!(BigWinTier::from_ratio(75.0), BigWinTier::EpicWin);
        assert_eq!(BigWinTier::from_ratio(150.0), BigWinTier::UltraWin);
    }

    #[test]
    fn test_feature_type_multi_step() {
        assert!(FeatureType::FreeSpins.is_multi_step());
        assert!(FeatureType::HoldAndSpin.is_multi_step());
        assert!(!FeatureType::Respin.is_multi_step());
        assert!(!FeatureType::WheelBonus.is_multi_step());
    }

    #[test]
    fn test_jackpot_tier_level() {
        assert!(JackpotTier::Mini.level() < JackpotTier::Minor.level());
        assert!(JackpotTier::Minor.level() < JackpotTier::Major.level());
        assert!(JackpotTier::Major.level() < JackpotTier::Grand.level());
    }
}
