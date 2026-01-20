//! Game Info — Basic game metadata and mode

use serde::{Deserialize, Serialize};

/// Basic game metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameInfo {
    /// Game name (display)
    pub name: String,

    /// Unique game identifier
    pub id: String,

    /// Version string
    #[serde(default = "default_version")]
    pub version: String,

    /// Provider/studio name
    #[serde(default)]
    pub provider: Option<String>,

    /// Game volatility level
    #[serde(default)]
    pub volatility: Volatility,

    /// Target RTP (0.0 - 1.0)
    #[serde(default = "default_rtp")]
    pub target_rtp: f64,

    /// Game description
    #[serde(default)]
    pub description: Option<String>,

    /// Theme tags
    #[serde(default)]
    pub tags: Vec<String>,
}

fn default_version() -> String {
    "1.0.0".to_string()
}

fn default_rtp() -> f64 {
    0.965 // 96.5%
}

impl GameInfo {
    /// Create new game info with minimal required fields
    pub fn new(name: impl Into<String>, id: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            id: id.into(),
            version: default_version(),
            provider: None,
            volatility: Volatility::default(),
            target_rtp: default_rtp(),
            description: None,
            tags: Vec::new(),
        }
    }

    /// Builder: set provider
    pub fn with_provider(mut self, provider: impl Into<String>) -> Self {
        self.provider = Some(provider.into());
        self
    }

    /// Builder: set volatility
    pub fn with_volatility(mut self, volatility: Volatility) -> Self {
        self.volatility = volatility;
        self
    }

    /// Builder: set target RTP
    pub fn with_rtp(mut self, rtp: f64) -> Self {
        self.target_rtp = rtp.clamp(0.0, 1.0);
        self
    }
}

impl Default for GameInfo {
    fn default() -> Self {
        Self::new("Unnamed Game", "unnamed")
    }
}

/// Game volatility level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Volatility {
    /// Low volatility — frequent small wins
    Low,
    /// Medium-low volatility
    MediumLow,
    /// Medium volatility — balanced
    #[default]
    Medium,
    /// Medium-high volatility
    MediumHigh,
    /// High volatility — rare big wins
    High,
    /// Very high volatility — very rare huge wins
    VeryHigh,
}

impl Volatility {
    /// Get numeric value (0.0 - 1.0) for interpolation
    pub fn as_factor(&self) -> f64 {
        match self {
            Self::Low => 0.0,
            Self::MediumLow => 0.2,
            Self::Medium => 0.4,
            Self::MediumHigh => 0.6,
            Self::High => 0.8,
            Self::VeryHigh => 1.0,
        }
    }

    /// Create from string
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "low" => Some(Self::Low),
            "medium_low" | "medium-low" | "mediumlow" => Some(Self::MediumLow),
            "medium" | "med" => Some(Self::Medium),
            "medium_high" | "medium-high" | "mediumhigh" => Some(Self::MediumHigh),
            "high" => Some(Self::High),
            "very_high" | "very-high" | "veryhigh" | "extreme" => Some(Self::VeryHigh),
            _ => None,
        }
    }
}

/// Game operating mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum GameMode {
    /// GDD-Only mode — scripted outcomes, no RNG
    /// Used for demos, presentations, audio design with predictable sequences
    #[default]
    GddOnly,

    /// Math-Driven mode — real probability distribution
    /// Uses math model for realistic RTP, hit frequency, feature triggers
    MathDriven,
}

impl GameMode {
    /// Check if this is scripted mode
    pub fn is_scripted(&self) -> bool {
        matches!(self, Self::GddOnly)
    }

    /// Check if this uses real math
    pub fn is_probabilistic(&self) -> bool {
        matches!(self, Self::MathDriven)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_game_info_builder() {
        let info = GameInfo::new("Test Game", "test_game")
            .with_provider("Test Studio")
            .with_volatility(Volatility::High)
            .with_rtp(0.96);

        assert_eq!(info.name, "Test Game");
        assert_eq!(info.id, "test_game");
        assert_eq!(info.provider, Some("Test Studio".to_string()));
        assert_eq!(info.volatility, Volatility::High);
        assert!((info.target_rtp - 0.96).abs() < 0.001);
    }

    #[test]
    fn test_volatility_factor() {
        assert!((Volatility::Low.as_factor() - 0.0).abs() < 0.001);
        assert!((Volatility::Medium.as_factor() - 0.4).abs() < 0.001);
        assert!((Volatility::VeryHigh.as_factor() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_volatility_from_str() {
        assert_eq!(Volatility::from_str("high"), Some(Volatility::High));
        assert_eq!(Volatility::from_str("medium-low"), Some(Volatility::MediumLow));
        assert_eq!(Volatility::from_str("invalid"), None);
    }

    #[test]
    fn test_game_mode() {
        assert!(GameMode::GddOnly.is_scripted());
        assert!(!GameMode::GddOnly.is_probabilistic());
        assert!(!GameMode::MathDriven.is_scripted());
        assert!(GameMode::MathDriven.is_probabilistic());
    }
}
