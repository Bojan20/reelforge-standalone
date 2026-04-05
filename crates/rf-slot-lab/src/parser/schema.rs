//! GDD Schema Validation — FM-48
//!
//! Typed schema validation rules for GDD documents.
//! Validates structure, field types, required fields, and value ranges.

use super::{GddDocument, GddParseError};

/// Schema validation configuration.
#[derive(Debug, Clone)]
pub struct GddSchema {
    /// Require game.id field
    pub require_game_id: bool,
    /// Require game.name field
    pub require_game_name: bool,
    /// Require at least one symbol
    pub require_symbols: bool,
    /// Require grid configuration
    pub require_grid: bool,
    /// Minimum number of reels
    pub min_reels: u8,
    /// Maximum number of reels
    pub max_reels: u8,
    /// Minimum number of rows
    pub min_rows: u8,
    /// Maximum number of rows
    pub max_rows: u8,
    /// Valid volatility values
    pub valid_volatilities: Vec<String>,
    /// Valid win mechanism types
    pub valid_win_mechanisms: Vec<String>,
    /// Valid symbol types
    pub valid_symbol_types: Vec<String>,
    /// Valid feature types
    pub valid_feature_types: Vec<String>,
    /// Maximum symbol ID
    pub max_symbol_id: u32,
    /// Maximum name length
    pub max_name_length: usize,
    /// RTP range (min, max)
    pub rtp_range: (f64, f64),
}

impl Default for GddSchema {
    fn default() -> Self {
        Self {
            require_game_id: true,
            require_game_name: true,
            require_symbols: false,
            require_grid: true,
            min_reels: 1,
            max_reels: 10,
            min_rows: 1,
            max_rows: 10,
            valid_volatilities: vec![
                "low".into(),
                "medium".into(),
                "medium_high".into(),
                "high".into(),
                "very_high".into(),
                "extreme".into(),
            ],
            valid_win_mechanisms: vec![
                "paylines".into(),
                "ways".into(),
                "ways_243".into(),
                "ways_1024".into(),
                "cluster".into(),
                "megaways".into(),
            ],
            valid_symbol_types: vec![
                "regular".into(),
                "wild".into(),
                "scatter".into(),
                "bonus".into(),
                "expanding_wild".into(),
                "sticky_wild".into(),
                "mystery".into(),
                "multiplier".into(),
                "collector".into(),
            ],
            valid_feature_types: vec![
                "free_spins".into(),
                "cascades".into(),
                "hold_and_win".into(),
                "jackpot".into(),
                "gamble".into(),
                "multiplier".into(),
                "expanding_wild".into(),
                "sticky_wild".into(),
                "pick_bonus".into(),
                "wheel_bonus".into(),
                "trail_bonus".into(),
                "progressive".into(),
                "mystery_scatter".into(),
                "cluster_pay".into(),
                "megaways".into(),
            ],
            max_symbol_id: 999,
            max_name_length: 256,
            rtp_range: (0.80, 0.999),
        }
    }
}

impl GddSchema {
    /// Validate a GDD document against this schema.
    pub fn validate(&self, doc: &GddDocument) -> Result<Vec<String>, GddParseError> {
        let mut warnings = Vec::new();

        // ── Required Fields ──
        if self.require_game_name && doc.game.name.is_empty() {
            return Err(GddParseError::MissingField("game.name".into()));
        }

        if self.require_game_id && doc.game.id.is_empty() {
            return Err(GddParseError::MissingField("game.id".into()));
        }

        // ── Name Length ──
        if doc.game.name.len() > self.max_name_length {
            return Err(GddParseError::ValidationError(format!(
                "game.name exceeds max length: {} > {}",
                doc.game.name.len(),
                self.max_name_length
            )));
        }

        if doc.game.id.len() > self.max_name_length {
            return Err(GddParseError::ValidationError(format!(
                "game.id exceeds max length: {} > {}",
                doc.game.id.len(),
                self.max_name_length
            )));
        }

        // ── Game ID Format ──
        if !doc
            .game
            .id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            return Err(GddParseError::InvalidValue(format!(
                "game.id must be alphanumeric with underscores/hyphens, got: {}",
                doc.game.id
            )));
        }

        // ── Grid ──
        if doc.grid.reels < self.min_reels || doc.grid.reels > self.max_reels {
            return Err(GddParseError::ValidationError(format!(
                "grid.reels must be {}-{}, got: {}",
                self.min_reels, self.max_reels, doc.grid.reels
            )));
        }

        if doc.grid.rows < self.min_rows || doc.grid.rows > self.max_rows {
            return Err(GddParseError::ValidationError(format!(
                "grid.rows must be {}-{}, got: {}",
                self.min_rows, self.max_rows, doc.grid.rows
            )));
        }

        // ── Volatility ──
        if let Some(ref vol) = doc.game.volatility {
            let vol_lower = vol.to_lowercase();
            if !self.valid_volatilities.contains(&vol_lower) {
                warnings.push(format!(
                    "Unknown volatility '{}', valid values: {:?}",
                    vol, self.valid_volatilities
                ));
            }
        }

        // ── RTP ──
        if let Some(rtp) = doc.game.target_rtp
            && (rtp < self.rtp_range.0 || rtp > self.rtp_range.1) {
                return Err(GddParseError::InvalidValue(format!(
                    "target_rtp must be {:.2}-{:.3}, got: {:.4}",
                    self.rtp_range.0, self.rtp_range.1, rtp
                )));
            }

        // ── Win Mechanism ──
        let mech_lower = doc.win_mechanism.to_lowercase();
        if !self.valid_win_mechanisms.contains(&mech_lower) {
            warnings.push(format!(
                "Unknown win_mechanism '{}', valid values: {:?}",
                doc.win_mechanism, self.valid_win_mechanisms
            ));
        }

        // ── Symbols ──
        if self.require_symbols && doc.symbols.is_empty() {
            return Err(GddParseError::MissingField(
                "symbols (at least one required)".into(),
            ));
        }

        for (i, sym) in doc.symbols.iter().enumerate() {
            if sym.name.is_empty() {
                return Err(GddParseError::MissingField(format!("symbols[{}].name", i)));
            }

            if sym.id > self.max_symbol_id {
                return Err(GddParseError::InvalidValue(format!(
                    "symbols[{}].id exceeds max: {} > {}",
                    i, sym.id, self.max_symbol_id
                )));
            }

            let type_lower = sym.symbol_type.to_lowercase();
            if !self.valid_symbol_types.contains(&type_lower) {
                warnings.push(format!(
                    "symbols[{}] '{}' has unknown type '{}', valid: {:?}",
                    i, sym.name, sym.symbol_type, self.valid_symbol_types
                ));
            }
        }

        // ── Check for duplicate symbol IDs ──
        let mut seen_ids = std::collections::HashSet::new();
        for sym in &doc.symbols {
            if !seen_ids.insert(sym.id) {
                return Err(GddParseError::ValidationError(format!(
                    "Duplicate symbol ID: {}",
                    sym.id
                )));
            }
        }

        // ── Features ──
        for (i, feat) in doc.features.iter().enumerate() {
            let type_lower = feat.feature_type.to_lowercase();
            if !self.valid_feature_types.iter().any(|v| v == &type_lower) {
                warnings.push(format!(
                    "features[{}] has unknown type '{}', valid: {:?}",
                    i, feat.feature_type, self.valid_feature_types
                ));
            }

            if feat.trigger.is_empty() {
                warnings.push(format!(
                    "features[{}] '{}' has empty trigger",
                    i, feat.feature_type
                ));
            }
        }

        // ── Win Tiers ──
        for (i, tier) in doc.win_tiers.iter().enumerate() {
            if tier.name.is_empty() {
                warnings.push(format!("win_tiers[{}] has empty name", i));
            }

            if let (Some(min), Some(max)) = (tier.min_ratio, tier.max_ratio)
                && min >= max {
                    return Err(GddParseError::InvalidValue(format!(
                        "win_tiers[{}] '{}': min_ratio ({}) must be less than max_ratio ({})",
                        i, tier.name, min, max
                    )));
                }
        }

        // ── Math Model ──
        if let Some(ref math) = doc.math
            && (math.target_rtp < self.rtp_range.0 || math.target_rtp > self.rtp_range.1) {
                return Err(GddParseError::InvalidValue(format!(
                    "math.target_rtp must be {:.2}-{:.3}, got: {:.4}",
                    self.rtp_range.0, self.rtp_range.1, math.target_rtp
                )));
            }

        Ok(warnings)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::{GddGame, GddGrid};

    fn minimal_doc() -> GddDocument {
        GddDocument {
            game: GddGame {
                name: "Test".into(),
                id: "test_game".into(),
                provider: None,
                volatility: None,
                target_rtp: None,
            },
            grid: GddGrid {
                reels: 5,
                rows: 3,
                paylines: None,
            },
            symbols: vec![],
            win_mechanism: "paylines".into(),
            features: vec![],
            win_tiers: vec![],
            math: None,
        }
    }

    #[test]
    fn test_minimal_valid() {
        let schema = GddSchema::default();
        let result = schema.validate(&minimal_doc());
        assert!(result.is_ok());
    }

    #[test]
    fn test_empty_game_name() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.game.name = String::new();
        assert!(schema.validate(&doc).is_err());
    }

    #[test]
    fn test_empty_game_id() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.game.id = String::new();
        assert!(schema.validate(&doc).is_err());
    }

    #[test]
    fn test_invalid_game_id_chars() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.game.id = "test game!@#".into();
        assert!(schema.validate(&doc).is_err());
    }

    #[test]
    fn test_reels_out_of_range() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.grid.reels = 0;
        assert!(schema.validate(&doc).is_err());
    }

    #[test]
    fn test_rtp_out_of_range() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.game.target_rtp = Some(1.5);
        assert!(schema.validate(&doc).is_err());
    }

    #[test]
    fn test_unknown_volatility_warning() {
        let schema = GddSchema::default();
        let mut doc = minimal_doc();
        doc.game.volatility = Some("crazy".into());
        let warnings = schema.validate(&doc).unwrap();
        assert!(!warnings.is_empty());
    }
}
