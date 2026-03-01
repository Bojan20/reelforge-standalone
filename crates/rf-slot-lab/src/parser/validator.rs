//! GDD Constraint Validator — FM-49
//!
//! Cross-field constraint validation for GDD documents.
//! Checks logical consistency: feature compatibility, grid/mechanism alignment,
//! symbol pay table integrity, and FluxMacro-specific requirements.

use super::{GddDocument, GddParseError};

/// Constraint validation results.
#[derive(Debug)]
pub struct ValidationReport {
    /// Validation passed (no errors)
    pub valid: bool,
    /// Warning messages (non-fatal)
    pub warnings: Vec<String>,
    /// Error messages (fatal)
    pub errors: Vec<String>,
    /// Suggestion messages
    pub suggestions: Vec<String>,
}

impl ValidationReport {
    fn new() -> Self {
        Self {
            valid: true,
            warnings: Vec::new(),
            errors: Vec::new(),
            suggestions: Vec::new(),
        }
    }

    fn add_error(&mut self, msg: String) {
        self.valid = false;
        self.errors.push(msg);
    }

    fn add_warning(&mut self, msg: String) {
        self.warnings.push(msg);
    }

    fn add_suggestion(&mut self, msg: String) {
        self.suggestions.push(msg);
    }
}

/// Validate GDD document constraints.
pub fn validate_constraints(doc: &GddDocument) -> Result<ValidationReport, GddParseError> {
    let mut report = ValidationReport::new();

    validate_grid_mechanism(doc, &mut report);
    validate_symbol_pays(doc, &mut report);
    validate_feature_compatibility(doc, &mut report);
    validate_win_tier_coverage(doc, &mut report);
    validate_math_consistency(doc, &mut report);
    validate_fluxmacro_requirements(doc, &mut report);

    Ok(report)
}

// ─── Grid ↔ Mechanism Alignment ─────────────────────────────────────────────

fn validate_grid_mechanism(doc: &GddDocument, report: &mut ValidationReport) {
    let mech = doc.win_mechanism.to_lowercase();

    match mech.as_str() {
        "megaways" => {
            // Megaways typically requires 6 reels
            if doc.grid.reels < 5 {
                report.add_warning(format!(
                    "Megaways typically uses 5-6 reels, got {}",
                    doc.grid.reels
                ));
            }
            // Paylines don't apply to megaways
            if doc.grid.paylines.is_some() {
                report.add_warning("Megaways uses ways, not fixed paylines".into());
            }
        }
        "ways" | "ways_243" => {
            // 243 ways = 3^5 (5 reels, 3 rows)
            if doc.grid.reels != 5 || doc.grid.rows != 3 {
                report.add_warning(format!(
                    "243 ways expects 5x3 grid, got {}x{}",
                    doc.grid.reels, doc.grid.rows
                ));
            }
        }
        "ways_1024" => {
            // 1024 ways = 4^5 (5 reels, 4 rows)
            if doc.grid.reels != 5 || doc.grid.rows != 4 {
                report.add_warning(format!(
                    "1024 ways expects 5x4 grid, got {}x{}",
                    doc.grid.reels, doc.grid.rows
                ));
            }
        }
        "cluster" => {
            // Cluster pay typically needs larger grid
            if doc.grid.reels < 5 || doc.grid.rows < 5 {
                report.add_warning(format!(
                    "Cluster pay typically uses 5x5+ grid, got {}x{}",
                    doc.grid.reels, doc.grid.rows
                ));
            }
        }
        _ => {}
    }
}

// ─── Symbol Pay Table ────────────────────────────────────────────────────────

fn validate_symbol_pays(doc: &GddDocument, report: &mut ValidationReport) {
    if doc.symbols.is_empty() {
        return;
    }

    let has_wild = doc.symbols.iter().any(|s| {
        s.symbol_type.to_lowercase() == "wild"
    });

    let has_scatter = doc.symbols.iter().any(|s| {
        s.symbol_type.to_lowercase() == "scatter"
    });

    // Check feature triggers reference existing symbols
    let has_free_spins = doc.features.iter().any(|f| {
        f.feature_type.to_lowercase().contains("free_spin")
    });

    if has_free_spins && !has_scatter {
        report.add_warning(
            "Free spins feature but no scatter symbol defined — trigger mechanism unclear".into(),
        );
    }

    // Check pay values are ascending (more symbols = higher pay)
    for sym in &doc.symbols {
        if sym.pays.len() >= 2 {
            for pair in sym.pays.windows(2) {
                if pair[0] > pair[1] {
                    report.add_warning(format!(
                        "Symbol '{}' has non-ascending pays: {:.1} > {:.1}",
                        sym.name, pair[0], pair[1]
                    ));
                }
            }
        }
    }

    // Suggest wild if not present
    if !has_wild && !doc.symbols.is_empty() {
        report.add_suggestion("Consider adding a wild symbol for better gameplay".into());
    }
}

// ─── Feature Compatibility ───────────────────────────────────────────────────

fn validate_feature_compatibility(doc: &GddDocument, report: &mut ValidationReport) {
    let feature_types: Vec<String> = doc
        .features
        .iter()
        .map(|f| f.feature_type.to_lowercase())
        .collect();

    // Check for conflicting features
    if feature_types.contains(&"cascades".into()) && feature_types.contains(&"megaways".into()) {
        // This is actually valid — many games combine these
        report.add_suggestion(
            "Cascades + Megaways is a complex combination — ensure audio covers all states".into(),
        );
    }

    // Hold and Win + Progressive should have jackpot tiers
    if feature_types.contains(&"hold_and_win".into())
        && feature_types.contains(&"progressive".into())
    {
        if doc.win_tiers.len() < 3 {
            report.add_warning(
                "Hold and Win + Progressive typically needs 3+ win tiers (Mini, Minor, Major, Grand)".into(),
            );
        }
    }

    // Gamble feature needs careful audio design
    if feature_types.contains(&"gamble".into()) {
        report.add_suggestion(
            "Gamble feature detected — ensure distinct win/lose audio cues for responsible gambling UX".into(),
        );
    }

    // Multiple bonus features need distinct audio
    let bonus_count = feature_types
        .iter()
        .filter(|f| {
            ["free_spins", "pick_bonus", "wheel_bonus", "trail_bonus", "hold_and_win"]
                .contains(&f.as_str())
        })
        .count();

    if bonus_count > 3 {
        report.add_warning(format!(
            "{} bonus features detected — each needs unique audio identity to avoid confusion",
            bonus_count
        ));
    }
}

// ─── Win Tier Coverage ───────────────────────────────────────────────────────

fn validate_win_tier_coverage(doc: &GddDocument, report: &mut ValidationReport) {
    if doc.win_tiers.is_empty() {
        report.add_suggestion(
            "No win tiers defined — default tiers will be used. Consider defining custom tiers.".into(),
        );
        return;
    }

    // Check for gaps in win tier ranges
    let mut sorted_tiers: Vec<_> = doc.win_tiers.iter().collect();
    sorted_tiers.sort_by(|a, b| {
        let a_min = a.min_ratio.unwrap_or(0.0);
        let b_min = b.min_ratio.unwrap_or(0.0);
        a_min.partial_cmp(&b_min).unwrap_or(std::cmp::Ordering::Equal)
    });

    for i in 0..sorted_tiers.len().saturating_sub(1) {
        let current_max = sorted_tiers[i].max_ratio.unwrap_or(f64::MAX);
        let next_min = sorted_tiers[i + 1].min_ratio.unwrap_or(0.0);

        if current_max < next_min {
            report.add_warning(format!(
                "Gap in win tier coverage between '{}' (max={:.1}x) and '{}' (min={:.1}x)",
                sorted_tiers[i].name, current_max,
                sorted_tiers[i + 1].name, next_min
            ));
        }
    }
}

// ─── Math Consistency ────────────────────────────────────────────────────────

fn validate_math_consistency(doc: &GddDocument, report: &mut ValidationReport) {
    if let Some(ref math) = doc.math {
        // Check game.target_rtp vs math.target_rtp
        if let Some(game_rtp) = doc.game.target_rtp {
            let diff = (game_rtp - math.target_rtp).abs();
            if diff > 0.001 {
                report.add_error(format!(
                    "RTP mismatch: game.target_rtp={:.4} vs math.target_rtp={:.4}",
                    game_rtp, math.target_rtp
                ));
            }
        }

        // Check symbol weights reference existing symbols
        for (sym_name, weights) in &math.symbol_weights {
            let found = doc.symbols.iter().any(|s| &s.name == sym_name);
            if !found && !doc.symbols.is_empty() {
                report.add_warning(format!(
                    "math.symbol_weights references unknown symbol '{}'",
                    sym_name
                ));
            }

            // Weight count should match reel count
            if weights.len() != doc.grid.reels as usize {
                report.add_warning(format!(
                    "Symbol '{}' has {} weights but grid has {} reels",
                    sym_name,
                    weights.len(),
                    doc.grid.reels
                ));
            }
        }
    }
}

// ─── FluxMacro Requirements ─────────────────────────────────────────────────

fn validate_fluxmacro_requirements(doc: &GddDocument, report: &mut ValidationReport) {
    // FluxMacro needs volatility for profile generation
    if doc.game.volatility.is_none() {
        report.add_warning(
            "No volatility specified — FluxMacro volatility.profile.generate will use 'medium' default".into(),
        );
    }

    // FluxMacro needs target_rtp for loudness targeting
    if doc.game.target_rtp.is_none() {
        report.add_suggestion(
            "No target_rtp — FluxMacro will use 96.5% default for audio budget calculations".into(),
        );
    }

    // FluxMacro needs features for ADB generation
    if doc.features.is_empty() {
        report.add_warning(
            "No features defined — FluxMacro adb.generate will produce minimal Audio Design Brief".into(),
        );
    }

    // FluxMacro prefers symbols for naming.validate step
    if doc.symbols.is_empty() {
        report.add_suggestion(
            "No symbols defined — FluxMacro naming.validate will only check format, not symbol coverage".into(),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::{GddFeature, GddGame, GddGrid, GddWinTier};

    fn minimal_doc() -> GddDocument {
        GddDocument {
            game: GddGame {
                name: "Test".into(),
                id: "test".into(),
                provider: None,
                volatility: Some("high".into()),
                target_rtp: Some(0.965),
            },
            grid: GddGrid {
                reels: 5,
                rows: 3,
                paylines: Some(20),
            },
            symbols: vec![],
            win_mechanism: "paylines".into(),
            features: vec![],
            win_tiers: vec![],
            math: None,
        }
    }

    #[test]
    fn test_minimal_passes() {
        let report = validate_constraints(&minimal_doc()).unwrap();
        assert!(report.valid);
    }

    #[test]
    fn test_megaways_grid_warning() {
        let mut doc = minimal_doc();
        doc.win_mechanism = "megaways".into();
        doc.grid.reels = 3;
        let report = validate_constraints(&doc).unwrap();
        assert!(!report.warnings.is_empty());
    }

    #[test]
    fn test_rtp_mismatch_error() {
        let mut doc = minimal_doc();
        doc.game.target_rtp = Some(0.96);
        doc.math = Some(crate::parser::GddMath {
            target_rtp: 0.94,
            volatility: None,
            symbol_weights: Default::default(),
        });
        let report = validate_constraints(&doc).unwrap();
        assert!(!report.valid);
    }

    #[test]
    fn test_fluxmacro_no_volatility_warning() {
        let mut doc = minimal_doc();
        doc.game.volatility = None;
        let report = validate_constraints(&doc).unwrap();
        assert!(report.warnings.iter().any(|w| w.contains("volatility")));
    }

    #[test]
    fn test_win_tier_gap_warning() {
        let mut doc = minimal_doc();
        doc.win_tiers = vec![
            GddWinTier {
                name: "Small".into(),
                min_ratio: Some(1.0),
                max_ratio: Some(5.0),
            },
            GddWinTier {
                name: "Big".into(),
                min_ratio: Some(20.0),
                max_ratio: Some(100.0),
            },
        ];
        let report = validate_constraints(&doc).unwrap();
        assert!(report.warnings.iter().any(|w| w.contains("Gap")));
    }

    #[test]
    fn test_many_bonus_features_warning() {
        let mut doc = minimal_doc();
        doc.features = vec![
            GddFeature {
                feature_type: "free_spins".into(),
                trigger: "scatter".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "pick_bonus".into(),
                trigger: "bonus".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "wheel_bonus".into(),
                trigger: "wheel".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "hold_and_win".into(),
                trigger: "coins".into(),
                params: Default::default(),
            },
        ];
        let report = validate_constraints(&doc).unwrap();
        assert!(report.warnings.iter().any(|w| w.contains("bonus features")));
    }
}
