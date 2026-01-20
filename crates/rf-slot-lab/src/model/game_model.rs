//! Game Model — Central game definition

use serde::{Deserialize, Serialize};

use crate::config::GridSpec;
use crate::symbols::StandardSymbolSet;
use crate::timing::TimingConfig;

use super::{GameInfo, GameMode, MathModel, WinMechanism, WinTierConfig};

/// Central game model — complete game definition
///
/// This is the main configuration structure that defines a slot game.
/// It can be created from a GDD document or programmatically.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameModel {
    /// Basic game information
    pub info: GameInfo,

    /// Grid configuration (reels × rows)
    pub grid: GridSpec,

    /// Symbol definitions
    #[serde(default)]
    pub symbols: SymbolSetConfig,

    /// Win mechanism (paylines, ways, cluster)
    #[serde(default)]
    pub win_mechanism: WinMechanism,

    /// Active feature IDs
    #[serde(default)]
    pub features: Vec<FeatureRef>,

    /// Win tier configuration
    #[serde(default)]
    pub win_tiers: WinTierConfig,

    /// Timing configuration
    #[serde(default)]
    pub timing: TimingConfig,

    /// Operating mode
    #[serde(default)]
    pub mode: GameMode,

    /// Math model (optional, for Math-Driven mode)
    #[serde(default)]
    pub math: Option<MathModel>,
}

impl GameModel {
    /// Create a new game model with required fields
    pub fn new(name: impl Into<String>, id: impl Into<String>) -> Self {
        Self {
            info: GameInfo::new(name, id),
            grid: GridSpec::default(),
            symbols: SymbolSetConfig::default(),
            win_mechanism: WinMechanism::default(),
            features: Vec::new(),
            win_tiers: WinTierConfig::default(),
            timing: TimingConfig::default(),
            mode: GameMode::default(),
            math: None,
        }
    }

    /// Create a standard 5x3 game
    pub fn standard_5x3(name: impl Into<String>, id: impl Into<String>) -> Self {
        Self {
            info: GameInfo::new(name, id),
            grid: GridSpec::standard_5x3(),
            symbols: SymbolSetConfig::Standard,
            win_mechanism: WinMechanism::standard_20_paylines(),
            features: vec![
                FeatureRef::builtin("free_spins"),
                FeatureRef::builtin("cascades"),
            ],
            win_tiers: WinTierConfig::standard(),
            timing: TimingConfig::normal(),
            mode: GameMode::GddOnly,
            math: None,
        }
    }

    /// Builder: set grid
    pub fn with_grid(mut self, grid: GridSpec) -> Self {
        self.grid = grid;
        self
    }

    /// Builder: set win mechanism
    pub fn with_win_mechanism(mut self, mechanism: WinMechanism) -> Self {
        self.win_mechanism = mechanism;
        self
    }

    /// Builder: add feature
    pub fn with_feature(mut self, feature: FeatureRef) -> Self {
        self.features.push(feature);
        self
    }

    /// Builder: set mode
    pub fn with_mode(mut self, mode: GameMode) -> Self {
        self.mode = mode;
        self
    }

    /// Builder: set math model
    pub fn with_math(mut self, math: MathModel) -> Self {
        self.math = Some(math);
        self.mode = GameMode::MathDriven;
        self
    }

    /// Builder: set timing
    pub fn with_timing(mut self, timing: TimingConfig) -> Self {
        self.timing = timing;
        self
    }

    /// Check if a feature is enabled
    pub fn has_feature(&self, feature_id: &str) -> bool {
        self.features.iter().any(|f| f.id == feature_id)
    }

    /// Get all enabled feature IDs
    pub fn feature_ids(&self) -> Vec<&str> {
        self.features.iter().map(|f| f.id.as_str()).collect()
    }

    /// Check if using math-driven mode
    pub fn is_math_driven(&self) -> bool {
        self.mode.is_probabilistic() && self.math.is_some()
    }

    /// Validate the game model
    pub fn validate(&self) -> Result<(), GameModelError> {
        // Check grid
        if self.grid.reels == 0 || self.grid.rows == 0 {
            return Err(GameModelError::InvalidGrid("Grid must have at least 1 reel and 1 row"));
        }

        // Check info
        if self.info.name.is_empty() {
            return Err(GameModelError::InvalidInfo("Game name cannot be empty"));
        }

        if self.info.id.is_empty() {
            return Err(GameModelError::InvalidInfo("Game ID cannot be empty"));
        }

        // Check RTP bounds
        if self.info.target_rtp <= 0.0 || self.info.target_rtp > 1.0 {
            return Err(GameModelError::InvalidInfo("Target RTP must be between 0 and 1"));
        }

        // Check math model if math-driven
        if self.mode.is_probabilistic() && self.math.is_none() {
            return Err(GameModelError::MissingMath);
        }

        Ok(())
    }
}

impl Default for GameModel {
    fn default() -> Self {
        Self::standard_5x3("Default Game", "default")
    }
}

/// Symbol set configuration
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum SymbolSetConfig {
    /// Use standard symbol set
    #[default]
    Standard,

    /// Custom symbols from GDD
    Custom {
        symbols: Vec<SymbolDef>,
    },
}

impl SymbolSetConfig {
    /// Convert to StandardSymbolSet
    pub fn to_symbol_set(&self) -> StandardSymbolSet {
        match self {
            Self::Standard => StandardSymbolSet::new(),
            Self::Custom { symbols: _ } => {
                // TODO: Convert custom symbols
                StandardSymbolSet::new()
            }
        }
    }
}

/// Symbol definition from GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SymbolDef {
    /// Symbol ID
    pub id: u32,
    /// Symbol name
    pub name: String,
    /// Symbol type
    pub symbol_type: String,
    /// Pay values for 3/4/5 of a kind
    #[serde(default)]
    pub pays: Vec<f64>,
    /// Symbol tier (0 = highest)
    #[serde(default)]
    pub tier: u8,
}

/// Feature reference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureRef {
    /// Feature ID
    pub id: String,

    /// Feature configuration (optional overrides)
    #[serde(default)]
    pub config: Option<serde_json::Value>,

    /// Is this a built-in feature?
    #[serde(default)]
    pub builtin: bool,
}

impl FeatureRef {
    /// Reference a built-in feature
    pub fn builtin(id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            config: None,
            builtin: true,
        }
    }

    /// Reference a custom feature with config
    pub fn custom(id: impl Into<String>, config: serde_json::Value) -> Self {
        Self {
            id: id.into(),
            config: Some(config),
            builtin: false,
        }
    }
}

/// Game model validation errors
#[derive(Debug, Clone, thiserror::Error)]
pub enum GameModelError {
    #[error("Invalid grid: {0}")]
    InvalidGrid(&'static str),

    #[error("Invalid info: {0}")]
    InvalidInfo(&'static str),

    #[error("Math model required for Math-Driven mode")]
    MissingMath,

    #[error("Invalid feature: {0}")]
    InvalidFeature(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_game_model_creation() {
        let model = GameModel::new("Test Game", "test");
        assert_eq!(model.info.name, "Test Game");
        assert_eq!(model.info.id, "test");
    }

    #[test]
    fn test_game_model_builder() {
        let model = GameModel::new("Builder Test", "builder")
            .with_grid(GridSpec::standard_5x4())
            .with_win_mechanism(WinMechanism::ways_243())
            .with_feature(FeatureRef::builtin("free_spins"))
            .with_mode(GameMode::GddOnly);

        assert_eq!(model.grid.rows, 4);
        assert!(model.win_mechanism.is_ways());
        assert!(model.has_feature("free_spins"));
    }

    #[test]
    fn test_game_model_validation() {
        let valid = GameModel::standard_5x3("Valid", "valid");
        assert!(valid.validate().is_ok());

        let invalid_grid = GameModel {
            grid: GridSpec { reels: 0, rows: 3, paylines: 20 },
            ..Default::default()
        };
        assert!(invalid_grid.validate().is_err());

        let invalid_mode = GameModel {
            mode: GameMode::MathDriven,
            math: None,
            ..Default::default()
        };
        assert!(invalid_mode.validate().is_err());
    }

    #[test]
    fn test_feature_refs() {
        let builtin = FeatureRef::builtin("free_spins");
        assert!(builtin.builtin);
        assert!(builtin.config.is_none());

        let custom = FeatureRef::custom("custom_feature", serde_json::json!({"param": 42}));
        assert!(!custom.builtin);
        assert!(custom.config.is_some());
    }
}
