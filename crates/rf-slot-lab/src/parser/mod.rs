//! GDD Parser — Parse Game Design Documents into GameModel
//!
//! This module provides parsing functionality for GDD (Game Design Document)
//! files in JSON and YAML formats.
//!
//! ## Supported Formats
//!
//! - JSON (primary)
//! - YAML (planned)
//!
//! ## Usage
//!
//! ```rust,ignore
//! let parser = GddParser::new();
//! let model = parser.parse_json(json_string)?;
//! ```

// TODO: Implement in Phase 4
// mod gdd;
// mod schema;
// mod validator;

// pub use gdd::*;
// pub use schema::*;
// pub use validator::*;

use serde::{Deserialize, Serialize};

use crate::model::GameModel;

/// GDD Parser
pub struct GddParser {
    /// Validation limits
    pub limits: GddLimits,
}

/// Parsing limits for security
#[derive(Debug, Clone)]
pub struct GddLimits {
    pub max_name_length: usize,
    pub max_symbols: usize,
    pub max_paylines: usize,
    pub max_features: usize,
    pub max_reels: usize,
    pub max_rows: usize,
    pub max_pay_value: f64,
}

impl Default for GddLimits {
    fn default() -> Self {
        Self {
            max_name_length: 256,
            max_symbols: 50,
            max_paylines: 100,
            max_features: 20,
            max_reels: 10,
            max_rows: 10,
            max_pay_value: 100_000.0,
        }
    }
}

impl GddParser {
    /// Create a new parser
    pub fn new() -> Self {
        Self {
            limits: GddLimits::default(),
        }
    }

    /// Create parser with custom limits
    pub fn with_limits(limits: GddLimits) -> Self {
        Self { limits }
    }

    /// Parse JSON GDD into GameModel
    pub fn parse_json(&self, json: &str) -> Result<GameModel, GddParseError> {
        // Parse JSON
        let doc: GddDocument = serde_json::from_str(json)
            .map_err(|e| GddParseError::JsonError(e.to_string()))?;

        // Validate
        self.validate(&doc)?;

        // Convert to GameModel
        self.to_game_model(doc)
    }

    /// Validate GDD document
    pub fn validate(&self, doc: &GddDocument) -> Result<(), GddParseError> {
        // Check name length
        if doc.game.name.len() > self.limits.max_name_length {
            return Err(GddParseError::ValidationError(
                format!("Game name too long: {} > {}", doc.game.name.len(), self.limits.max_name_length)
            ));
        }

        // Check symbol count
        if doc.symbols.len() > self.limits.max_symbols {
            return Err(GddParseError::ValidationError(
                format!("Too many symbols: {} > {}", doc.symbols.len(), self.limits.max_symbols)
            ));
        }

        // Check grid
        if doc.grid.reels > self.limits.max_reels as u8 {
            return Err(GddParseError::ValidationError(
                format!("Too many reels: {} > {}", doc.grid.reels, self.limits.max_reels)
            ));
        }

        if doc.grid.rows > self.limits.max_rows as u8 {
            return Err(GddParseError::ValidationError(
                format!("Too many rows: {} > {}", doc.grid.rows, self.limits.max_rows)
            ));
        }

        Ok(())
    }

    /// Convert GDD document to GameModel
    fn to_game_model(&self, doc: GddDocument) -> Result<GameModel, GddParseError> {
        use crate::config::GridSpec;
        use crate::model::{GameInfo, GameMode, Volatility, WinMechanism};

        let info = GameInfo::new(&doc.game.name, &doc.game.id)
            .with_volatility(
                doc.game.volatility
                    .as_deref()
                    .and_then(Volatility::from_str)
                    .unwrap_or_default()
            )
            .with_rtp(doc.game.target_rtp.unwrap_or(0.965));

        let grid = GridSpec {
            reels: doc.grid.reels,
            rows: doc.grid.rows,
            paylines: doc.grid.paylines.unwrap_or(20),
        };

        let win_mechanism = match doc.win_mechanism.as_str() {
            "ways" => WinMechanism::ways_243(),
            "cluster" => WinMechanism::cluster_5(),
            "megaways" => WinMechanism::megaways_standard(),
            _ => WinMechanism::standard_20_paylines(),
        };

        Ok(GameModel {
            info,
            grid,
            win_mechanism,
            mode: GameMode::GddOnly,
            ..Default::default()
        })
    }
}

impl Default for GddParser {
    fn default() -> Self {
        Self::new()
    }
}

/// GDD Document structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddDocument {
    /// Game info
    pub game: GddGame,
    /// Grid configuration
    pub grid: GddGrid,
    /// Symbol definitions
    #[serde(default)]
    pub symbols: Vec<GddSymbol>,
    /// Win mechanism type
    #[serde(default = "default_win_mechanism")]
    pub win_mechanism: String,
    /// Feature definitions
    #[serde(default)]
    pub features: Vec<GddFeature>,
    /// Win tier definitions
    #[serde(default)]
    pub win_tiers: Vec<GddWinTier>,
    /// Math model (optional)
    #[serde(default)]
    pub math: Option<GddMath>,
}

fn default_win_mechanism() -> String {
    "paylines".to_string()
}

/// Game info in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddGame {
    pub name: String,
    pub id: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub volatility: Option<String>,
    #[serde(default)]
    pub target_rtp: Option<f64>,
}

/// Grid config in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddGrid {
    pub reels: u8,
    pub rows: u8,
    #[serde(default)]
    pub paylines: Option<u16>,
}

/// Symbol in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddSymbol {
    pub id: u32,
    pub name: String,
    #[serde(rename = "type")]
    pub symbol_type: String,
    #[serde(default)]
    pub pays: Vec<f64>,
    #[serde(default)]
    pub tier: u8,
}

/// Feature in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddFeature {
    #[serde(rename = "type")]
    pub feature_type: String,
    pub trigger: String,
    #[serde(flatten)]
    pub params: std::collections::HashMap<String, serde_json::Value>,
}

/// Win tier in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddWinTier {
    pub name: String,
    #[serde(default)]
    pub min_ratio: Option<f64>,
    #[serde(default)]
    pub max_ratio: Option<f64>,
}

/// Math model in GDD
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GddMath {
    pub target_rtp: f64,
    #[serde(default)]
    pub volatility: Option<String>,
    #[serde(default)]
    pub symbol_weights: std::collections::HashMap<String, Vec<u32>>,
}

/// GDD parsing errors
#[derive(Debug, thiserror::Error)]
pub enum GddParseError {
    #[error("JSON parse error: {0}")]
    JsonError(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("Invalid value: {0}")]
    InvalidValue(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_gdd() {
        let json = r#"{
            "game": {
                "name": "Test Game",
                "id": "test"
            },
            "grid": {
                "reels": 5,
                "rows": 3
            }
        }"#;

        let parser = GddParser::new();
        let model = parser.parse_json(json).unwrap();

        assert_eq!(model.info.name, "Test Game");
        assert_eq!(model.info.id, "test");
        assert_eq!(model.grid.reels, 5);
        assert_eq!(model.grid.rows, 3);
    }

    #[test]
    fn test_validation_limits() {
        let json = r#"{
            "game": {
                "name": "Test",
                "id": "test"
            },
            "grid": {
                "reels": 100,
                "rows": 3
            }
        }"#;

        let parser = GddParser::new();
        let result = parser.parse_json(json);

        assert!(result.is_err());
    }
}
