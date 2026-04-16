//! PAR File Parser — Probability Accounting Report
//!
//! Industry-standard math model import for slot games.
//! Every major slot studio (IGT, Aristocrat, Konami, AGS, Scientific Games)
//! generates PAR documents for regulators. This parser handles:
//!
//! - **CSV format** (AGS, Konami, Aristocrat, Everi exports)
//! - **JSON format** (modern studios, FluxForge native)
//! - **Auto-detect** (heuristic on header row)
//!
//! ## T2.1 + T2.2 combined:
//! - T2.1: Full PAR document parsing (all 5 sections: header, grid, symbols, paytable, features)
//! - T2.2: `auto_calibrate_win_tiers()` computes tier thresholds from RTP distribution
//!
//! ## Usage
//!
//! ```rust,ignore
//! let parser = ParParser::new();
//! let doc = parser.parse_json(json_str)?;
//! let report = parser.validate(&doc);
//! let tiers = auto_calibrate_win_tiers(&doc);
//! ```

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::model::{RegularWinTier, RegularWinConfig};

// ═══════════════════════════════════════════════════════════════════════════════
// CORE PAR STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════════

/// Volatility classification as used in PAR documents
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ParVolatility {
    Low,
    Medium,
    High,
    VeryHigh,
    Extreme,
}

impl ParVolatility {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().trim() {
            "low" | "l" | "1" => Self::Low,
            "medium" | "med" | "m" | "2" => Self::Medium,
            "high" | "h" | "3" => Self::High,
            "very_high" | "very high" | "veryhigh" | "vh" | "4" => Self::VeryHigh,
            "extreme" | "x" | "5" => Self::Extreme,
            _ => Self::Medium,
        }
    }

    /// Characteristic hit-frequency for this volatility (approximate)
    pub fn expected_hit_freq(&self) -> f64 {
        match self {
            Self::Low => 0.40,
            Self::Medium => 0.32,
            Self::High => 0.25,
            Self::VeryHigh => 0.18,
            Self::Extreme => 0.12,
        }
    }
}

impl std::fmt::Display for ParVolatility {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Low => write!(f, "LOW"),
            Self::Medium => write!(f, "MEDIUM"),
            Self::High => write!(f, "HIGH"),
            Self::VeryHigh => write!(f, "VERY_HIGH"),
            Self::Extreme => write!(f, "EXTREME"),
        }
    }
}

/// Symbol definition in a PAR document
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParSymbol {
    /// Symbol identifier (1-based, 0=empty/blank)
    pub id: u32,
    /// Display name
    pub name: String,
    /// Is this a wild symbol?
    #[serde(default)]
    pub is_wild: bool,
    /// Is this a scatter symbol?
    #[serde(default)]
    pub is_scatter: bool,
    /// Is this a multiplier wild?
    #[serde(default)]
    pub is_multiplier: bool,
    /// Multiplier value (if is_multiplier)
    #[serde(default)]
    pub multiplier_value: Option<f64>,
    /// Reel weights [reel_0..reel_N][stop_index] — raw strip counts
    /// reel_weights[r] = number of times this symbol appears on reel r strip
    #[serde(default)]
    pub reel_weights: Vec<u32>,
    /// Per-reel strip weights (if each reel has different weights)
    #[serde(default)]
    pub reel_strip_weights: Vec<Vec<u32>>,
}

impl ParSymbol {
    /// Get strip weight for a specific reel (falls back to reel_weights[reel])
    pub fn weight_on_reel(&self, reel: usize) -> u32 {
        if !self.reel_strip_weights.is_empty() {
            self.reel_strip_weights
                .get(reel)
                .and_then(|strips| {
                    // sum of the strip to get total appearance count
                    Some(strips.iter().sum())
                })
                .unwrap_or(0)
        } else {
            self.reel_weights.get(reel).copied().unwrap_or(0)
        }
    }
}

/// A single pay combination (win line)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PayCombination {
    /// Symbol ID
    pub symbol_id: u32,
    /// How many of this symbol in a row (3, 4, or 5)
    pub count: u8,
    /// Payout as multiplier of bet (e.g. 50.0 = 50x)
    pub payout_multiplier: f64,
    /// RTP contribution of this combination (0.0–1.0)
    #[serde(default)]
    pub rtp_contribution: f64,
    /// Hit frequency (times per 1000 spins)
    #[serde(default)]
    pub hit_frequency_per_1000: f64,
}

/// A feature (bonus, free spins, jackpot, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParFeature {
    /// Feature type identifier
    pub feature_type: ParFeatureType,
    /// Display name
    #[serde(default)]
    pub name: String,
    /// Trigger probability per spin (0.0–1.0)
    pub trigger_probability: f64,
    /// Average total payout multiplier when triggered
    #[serde(default)]
    pub avg_payout_multiplier: f64,
    /// RTP contribution (fraction of total RTP)
    #[serde(default)]
    pub rtp_contribution: f64,
    /// Average duration in spins (for free spins features)
    #[serde(default)]
    pub avg_duration_spins: f64,
    /// Retrigger probability (0.0 if none)
    #[serde(default)]
    pub retrigger_probability: f64,
}

/// Feature type classification
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ParFeatureType {
    FreeSpins,
    Bonus,
    PickBonus,
    HoldAndWin,
    Jackpot,
    Cascade,
    Megaways,
    Gamble,
    WheelBonus,
    CollectBonus,
    Other,
}

impl ParFeatureType {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().replace([' ', '-'], "_").as_str() {
            "free_spins" | "freespins" | "free_games" | "fg" => Self::FreeSpins,
            "bonus" | "bonus_game" => Self::Bonus,
            "pick_bonus" | "pick" | "picker" => Self::PickBonus,
            "hold_and_win" | "holdandwin" | "hold_spin" | "hold_and_spin" => Self::HoldAndWin,
            "jackpot" | "jackpots" | "progressive" => Self::Jackpot,
            "cascade" | "avalanche" | "tumble" => Self::Cascade,
            "megaways" => Self::Megaways,
            "gamble" | "risk" | "double_up" => Self::Gamble,
            "wheel" | "wheel_bonus" => Self::WheelBonus,
            "collect" | "collect_bonus" => Self::CollectBonus,
            _ => Self::Other,
        }
    }
}

/// RTP breakdown by source
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpBreakdown {
    /// Base game (line wins) RTP
    #[serde(default)]
    pub base_game_rtp: f64,
    /// Free spins / bonus feature RTP
    #[serde(default)]
    pub free_spins_rtp: f64,
    /// Pick/wheel/other bonus RTP
    #[serde(default)]
    pub bonus_rtp: f64,
    /// Jackpot contribution to RTP
    #[serde(default)]
    pub jackpot_rtp: f64,
    /// Gamble feature RTP
    #[serde(default)]
    pub gamble_rtp: f64,
    /// Computed total (sum of above)
    #[serde(default)]
    pub total_rtp: f64,
}

impl RtpBreakdown {
    /// Recompute total from components
    pub fn recompute_total(&mut self) {
        self.total_rtp = self.base_game_rtp
            + self.free_spins_rtp
            + self.bonus_rtp
            + self.jackpot_rtp
            + self.gamble_rtp;
    }

    /// Check if breakdown sums to target within tolerance
    pub fn is_valid(&self, target: f64, tolerance: f64) -> bool {
        (self.total_rtp - target).abs() <= tolerance
    }
}

/// Jackpot level definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParJackpotLevel {
    /// Level name (MINI, MINOR, MAJOR, GRAND, MEGA)
    pub name: String,
    /// Seed value (minimum payout)
    pub seed_value: f64,
    /// Trigger probability per spin
    pub trigger_probability: f64,
    /// RTP contribution
    #[serde(default)]
    pub rtp_contribution: f64,
}

/// Complete PAR document — parsed structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParDocument {
    // ═══ HEADER ═══
    /// Game display name
    pub game_name: String,
    /// Game identifier (short code)
    pub game_id: String,
    /// Target RTP (e.g. 96.50 → stored as 96.50, NOT 0.9650)
    pub rtp_target: f64,
    /// Volatility classification
    pub volatility: ParVolatility,
    /// Maximum single-spin payout (multiplier of max bet)
    #[serde(default)]
    pub max_exposure: f64,
    /// Maximum win multiplier from base game only
    #[serde(default)]
    pub max_win_base: f64,

    // ═══ GRID ═══
    pub reels: u8,
    pub rows: u8,
    /// Fixed paylines (0 = ways-to-win)
    #[serde(default)]
    pub paylines: u16,
    /// Ways to win (e.g. 243, 1024, 117649)
    #[serde(default)]
    pub ways_to_win: Option<u32>,

    // ═══ SYMBOL TABLE ═══
    #[serde(default)]
    pub symbols: Vec<ParSymbol>,

    // ═══ PAYTABLE ═══
    #[serde(default)]
    pub pay_combinations: Vec<PayCombination>,

    // ═══ FEATURE TRIGGERS ═══
    #[serde(default)]
    pub features: Vec<ParFeature>,

    // ═══ JACKPOT LEVELS ═══
    #[serde(default)]
    pub jackpot_levels: Vec<ParJackpotLevel>,

    // ═══ RTP BREAKDOWN ═══
    #[serde(default)]
    pub rtp_breakdown: RtpBreakdown,

    // ═══ HIT FREQUENCY ═══
    /// Overall hit frequency (fraction of spins that produce any win)
    #[serde(default)]
    pub hit_frequency: f64,
    /// Dead spin frequency = 1.0 - hit_frequency
    #[serde(default)]
    pub dead_spin_frequency: f64,

    // ═══ METADATA ═══
    /// Source format (csv, json, xlsx_csv)
    #[serde(default)]
    pub source_format: String,
    /// Studio/provider that produced this PAR
    #[serde(default)]
    pub provider: Option<String>,
    /// Version string from PAR header
    #[serde(default)]
    pub par_version: Option<String>,
}

impl Default for RtpBreakdown {
    fn default() -> Self {
        Self {
            base_game_rtp: 0.0,
            free_spins_rtp: 0.0,
            bonus_rtp: 0.0,
            jackpot_rtp: 0.0,
            gamble_rtp: 0.0,
            total_rtp: 0.0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VALIDATION
// ═══════════════════════════════════════════════════════════════════════════════

/// PAR validation finding severity
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ParFindingSeverity {
    Error,
    Warning,
    Info,
}

/// A single PAR validation finding
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParFinding {
    pub severity: ParFindingSeverity,
    pub field: String,
    pub message: String,
}

/// Complete PAR validation report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParValidationReport {
    pub valid: bool,
    pub findings: Vec<ParFinding>,
    pub rtp_delta: f64,
    pub computed_hit_frequency: f64,
}

impl ParValidationReport {
    fn new() -> Self {
        Self {
            valid: true,
            findings: Vec::new(),
            rtp_delta: 0.0,
            computed_hit_frequency: 0.0,
        }
    }

    fn error(&mut self, field: &str, message: &str) {
        self.valid = false;
        self.findings.push(ParFinding {
            severity: ParFindingSeverity::Error,
            field: field.to_string(),
            message: message.to_string(),
        });
    }

    fn warn(&mut self, field: &str, message: &str) {
        self.findings.push(ParFinding {
            severity: ParFindingSeverity::Warning,
            field: field.to_string(),
            message: message.to_string(),
        });
    }

    fn info(&mut self, field: &str, message: &str) {
        self.findings.push(ParFinding {
            severity: ParFindingSeverity::Info,
            field: field.to_string(),
            message: message.to_string(),
        });
    }

    pub fn errors(&self) -> impl Iterator<Item = &ParFinding> {
        self.findings
            .iter()
            .filter(|f| f.severity == ParFindingSeverity::Error)
    }

    pub fn warnings(&self) -> impl Iterator<Item = &ParFinding> {
        self.findings
            .iter()
            .filter(|f| f.severity == ParFindingSeverity::Warning)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAR PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse limits (security bounds)
#[derive(Debug, Clone)]
pub struct ParLimits {
    pub max_symbols: usize,
    pub max_pay_combinations: usize,
    pub max_features: usize,
    pub max_jackpot_levels: usize,
    pub max_reels: u8,
    pub max_rows: u8,
    pub max_rtp: f64,
    pub min_rtp: f64,
    pub max_payout_multiplier: f64,
}

impl Default for ParLimits {
    fn default() -> Self {
        Self {
            max_symbols: 64,
            max_pay_combinations: 512,
            max_features: 32,
            max_jackpot_levels: 8,
            max_reels: 12,
            max_rows: 12,
            max_rtp: 99.9,
            min_rtp: 60.0,
            max_payout_multiplier: 250_000.0,
        }
    }
}

/// PAR file parser
pub struct ParParser {
    pub limits: ParLimits,
}

/// PAR parse errors
#[derive(Debug, thiserror::Error)]
pub enum ParParseError {
    #[error("JSON parse error: {0}")]
    JsonError(String),

    #[error("CSV parse error on line {line}: {message}")]
    CsvError { line: usize, message: String },

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("Invalid value for '{field}': {message}")]
    InvalidValue { field: String, message: String },

    #[error("Security limit exceeded: {0}")]
    LimitExceeded(String),

    #[error("Auto-detect failed: content is not valid PAR CSV or JSON")]
    AutoDetectFailed,
}

impl Default for ParParser {
    fn default() -> Self {
        Self::new()
    }
}

impl ParParser {
    pub fn new() -> Self {
        Self {
            limits: ParLimits::default(),
        }
    }

    pub fn with_limits(limits: ParLimits) -> Self {
        Self { limits }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public parse methods
    // ─────────────────────────────────────────────────────────────────────────

    /// Parse JSON PAR (FluxForge native + modern studios)
    pub fn parse_json(&self, json: &str) -> Result<ParDocument, ParParseError> {
        let mut doc: ParDocument = serde_json::from_str(json)
            .map_err(|e| ParParseError::JsonError(e.to_string()))?;
        doc.source_format = "json".to_string();
        self.apply_limits(&doc)?;
        self.normalize(&mut doc);
        Ok(doc)
    }

    /// Parse CSV PAR (AGS, Konami, Aristocrat exports)
    /// Expected column order: section headers + key=value pairs
    pub fn parse_csv(&self, csv: &str) -> Result<ParDocument, ParParseError> {
        let mut doc = self.parse_csv_internal(csv, false)?;
        doc.source_format = "csv".to_string();
        self.apply_limits(&doc)?;
        self.normalize(&mut doc);
        Ok(doc)
    }

    /// Parse Excel-derived CSV (Scientific Games, IGT — different delimiters)
    pub fn parse_xlsx_csv(&self, csv: &str) -> Result<ParDocument, ParParseError> {
        let mut doc = self.parse_csv_internal(csv, true)?;
        doc.source_format = "xlsx_csv".to_string();
        self.apply_limits(&doc)?;
        self.normalize(&mut doc);
        Ok(doc)
    }

    /// Auto-detect format and parse
    pub fn parse_auto(&self, content: &str) -> Result<ParDocument, ParParseError> {
        let trimmed = content.trim();
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            return self.parse_json(content);
        }
        // Try CSV (comma or semicolon)
        self.parse_csv(content)
            .or_else(|_| self.parse_xlsx_csv(content))
            .map_err(|_| ParParseError::AutoDetectFailed)
    }

    /// Validate a parsed PAR document
    pub fn validate(&self, doc: &ParDocument) -> ParValidationReport {
        let mut report = ParValidationReport::new();

        // ── Header validation ─────────────────────────────────────────────────
        if doc.game_name.is_empty() {
            report.error("game_name", "Game name is required");
        }
        if doc.game_id.is_empty() {
            report.error("game_id", "Game ID is required");
        }
        if doc.rtp_target < self.limits.min_rtp || doc.rtp_target > self.limits.max_rtp {
            report.error(
                "rtp_target",
                &format!(
                    "RTP {:.2}% is outside allowed range [{:.1}%–{:.1}%]",
                    doc.rtp_target, self.limits.min_rtp, self.limits.max_rtp
                ),
            );
        }
        if doc.reels < 3 || doc.reels > self.limits.max_reels {
            report.error(
                "reels",
                &format!("Reel count {} is outside valid range [3–{}]", doc.reels, self.limits.max_reels),
            );
        }
        if doc.rows < 1 || doc.rows > self.limits.max_rows {
            report.error(
                "rows",
                &format!("Row count {} is outside valid range [1–{}]", doc.rows, self.limits.max_rows),
            );
        }

        // ── Paytable validation ───────────────────────────────────────────────
        if doc.pay_combinations.is_empty() {
            report.warn("pay_combinations", "No pay combinations defined — RTP computation will be unavailable");
        } else {
            // RTP breakdown crosscheck
            let computed_rtp: f64 = doc
                .pay_combinations
                .iter()
                .map(|c| c.rtp_contribution)
                .sum();
            let feature_rtp: f64 = doc.features.iter().map(|f| f.rtp_contribution).sum();
            let total_computed = computed_rtp + feature_rtp;
            let rtp_as_fraction = doc.rtp_target / 100.0;
            report.rtp_delta = (total_computed - rtp_as_fraction).abs();

            if total_computed > 0.0 && report.rtp_delta > 0.005 {
                report.warn(
                    "rtp_breakdown",
                    &format!(
                        "Computed RTP from combinations ({:.4}) + features ({:.4}) = {:.4} differs from target {:.4} by {:.4}",
                        computed_rtp, feature_rtp, total_computed, rtp_as_fraction, report.rtp_delta
                    ),
                );
            }

            // Check each combination
            for combo in &doc.pay_combinations {
                if combo.payout_multiplier > self.limits.max_payout_multiplier {
                    report.error(
                        "pay_combinations",
                        &format!(
                            "Symbol {} count {} has payout {:.0}x exceeding limit {:.0}x",
                            combo.symbol_id, combo.count, combo.payout_multiplier, self.limits.max_payout_multiplier
                        ),
                    );
                }
                if combo.count < 2 || combo.count > doc.reels {
                    report.warn(
                        "pay_combinations",
                        &format!("Symbol {} pay for count={} is unusual", combo.symbol_id, combo.count),
                    );
                }
            }
        }

        // ── Symbol validation ─────────────────────────────────────────────────
        let wild_count = doc.symbols.iter().filter(|s| s.is_wild).count();
        let scatter_count = doc.symbols.iter().filter(|s| s.is_scatter).count();
        if wild_count == 0 && !doc.symbols.is_empty() {
            report.info("symbols", "No wild symbol defined");
        }
        if scatter_count == 0 && doc.features.iter().any(|f| matches!(f.feature_type, ParFeatureType::FreeSpins)) {
            report.warn("symbols", "Free spins feature present but no scatter symbol defined");
        }

        // ── Hit frequency ─────────────────────────────────────────────────────
        if doc.hit_frequency > 0.0 {
            report.computed_hit_frequency = doc.hit_frequency;
            let expected = doc.volatility.expected_hit_freq();
            if (doc.hit_frequency - expected).abs() > 0.15 {
                report.warn(
                    "hit_frequency",
                    &format!(
                        "Hit frequency {:.1}% unusual for {:?} volatility (expected ~{:.1}%)",
                        doc.hit_frequency * 100.0,
                        doc.volatility,
                        expected * 100.0
                    ),
                );
            }
        }

        // ── RTP breakdown ─────────────────────────────────────────────────────
        if doc.rtp_breakdown.total_rtp > 0.0 {
            let breakdown_delta =
                (doc.rtp_breakdown.total_rtp - doc.rtp_target / 100.0).abs();
            if breakdown_delta > 0.001 {
                report.warn(
                    "rtp_breakdown",
                    &format!(
                        "RTP breakdown total {:.4} differs from target {:.4}",
                        doc.rtp_breakdown.total_rtp,
                        doc.rtp_target / 100.0
                    ),
                );
            }
        }

        report
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CSV parser (internal)
    // ─────────────────────────────────────────────────────────────────────────

    fn parse_csv_internal(
        &self,
        csv: &str,
        xlsx_mode: bool,
    ) -> Result<ParDocument, ParParseError> {
        let delimiter = if xlsx_mode { ';' } else { ',' };
        let mut doc = ParDocument {
            game_name: String::new(),
            game_id: String::new(),
            rtp_target: 0.0,
            volatility: ParVolatility::Medium,
            max_exposure: 0.0,
            max_win_base: 0.0,
            reels: 5,
            rows: 3,
            paylines: 0,
            ways_to_win: None,
            symbols: Vec::new(),
            pay_combinations: Vec::new(),
            features: Vec::new(),
            jackpot_levels: Vec::new(),
            rtp_breakdown: RtpBreakdown::default(),
            hit_frequency: 0.0,
            dead_spin_frequency: 0.0,
            source_format: String::new(),
            provider: None,
            par_version: None,
        };

        let mut current_section = String::new();
        let mut symbol_map: HashMap<u32, usize> = HashMap::new(); // id → index in doc.symbols

        for (line_idx, raw_line) in csv.lines().enumerate() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            // Section header detection (lines like "=== PAYTABLE ===" or "[SYMBOLS]")
            if (line.starts_with("===") && line.ends_with("==="))
                || (line.starts_with('[') && line.ends_with(']'))
            {
                current_section = line
                    .trim_matches(|c| c == '=' || c == '[' || c == ']' || c == ' ')
                    .to_uppercase();
                continue;
            }

            let cols: Vec<&str> = line.splitn(16, delimiter).collect();

            match current_section.as_str() {
                // ── HEADER section ────────────────────────────────────────────
                "HEADER" | "GAME" | "" => {
                    // key=value pairs or key,value pairs
                    if cols.len() >= 2 {
                        let key = cols[0].trim().to_lowercase();
                        let val = cols[1].trim();
                        match key.as_str() {
                            "game_name" | "name" | "game name" => {
                                doc.game_name = val.to_string();
                            }
                            "game_id" | "id" | "game id" | "game code" => {
                                doc.game_id = val.to_string();
                            }
                            "rtp" | "rtp_target" | "target rtp" | "return to player" => {
                                let v: f64 = self.parse_f64(val, "rtp_target", line_idx)?;
                                // Normalize: accept both 96.5 and 0.965
                                doc.rtp_target = if v <= 1.0 { v * 100.0 } else { v };
                            }
                            "volatility" | "variance" => {
                                doc.volatility = ParVolatility::from_str(val);
                            }
                            "reels" => {
                                doc.reels = self.parse_u8(val, "reels", line_idx)?;
                            }
                            "rows" | "rows per reel" => {
                                doc.rows = self.parse_u8(val, "rows", line_idx)?;
                            }
                            "paylines" | "lines" => {
                                doc.paylines = self.parse_u16(val, "paylines", line_idx)?;
                            }
                            "ways" | "ways_to_win" | "ways to win" => {
                                doc.ways_to_win =
                                    Some(self.parse_u32(val, "ways_to_win", line_idx)?);
                            }
                            "max_win" | "max win" | "max exposure" | "maximum exposure" => {
                                doc.max_exposure =
                                    self.parse_f64(val, "max_exposure", line_idx)?;
                            }
                            "hit_frequency" | "hit frequency" | "hit freq" | "hit rate" => {
                                let v = self.parse_f64(val, "hit_frequency", line_idx)?;
                                doc.hit_frequency = if v > 1.0 { v / 100.0 } else { v };
                            }
                            "provider" | "studio" | "developer" => {
                                doc.provider = Some(val.to_string());
                            }
                            "par_version" | "par version" | "version" => {
                                doc.par_version = Some(val.to_string());
                            }
                            _ => {} // Unknown header fields silently ignored
                        }
                    }
                }

                // ── SYMBOLS section ───────────────────────────────────────────
                // Expected: symbol_id, name, is_wild, is_scatter, reel_1_weight, ...
                "SYMBOLS" | "SYMBOL TABLE" | "SYMBOL_TABLE" => {
                    if cols.len() < 2 {
                        continue;
                    }
                    // Skip column headers
                    if cols[0].trim().to_lowercase() == "id"
                        || cols[0].trim().to_lowercase() == "symbol_id"
                    {
                        continue;
                    }
                    let id = match cols[0].trim().parse::<u32>() {
                        Ok(v) => v,
                        Err(_) => continue, // Skip non-numeric IDs silently
                    };
                    let name = cols.get(1).map(|s| s.trim().to_string()).unwrap_or_default();
                    let is_wild = cols
                        .get(2)
                        .map(|s| Self::parse_bool(s.trim()))
                        .unwrap_or(false);
                    let is_scatter = cols
                        .get(3)
                        .map(|s| Self::parse_bool(s.trim()))
                        .unwrap_or(false);

                    // Remaining columns = reel weights
                    let reel_weights: Vec<u32> = cols[4..]
                        .iter()
                        .filter_map(|s| s.trim().parse::<u32>().ok())
                        .collect();

                    if doc.symbols.len() >= self.limits.max_symbols {
                        return Err(ParParseError::LimitExceeded(format!(
                            "Too many symbols (max {})",
                            self.limits.max_symbols
                        )));
                    }

                    let idx = doc.symbols.len();
                    doc.symbols.push(ParSymbol {
                        id,
                        name,
                        is_wild,
                        is_scatter,
                        is_multiplier: false,
                        multiplier_value: None,
                        reel_weights,
                        reel_strip_weights: Vec::new(),
                    });
                    symbol_map.insert(id, idx);
                }

                // ── PAYTABLE section ──────────────────────────────────────────
                // Expected: symbol_id, count, payout_multiplier, rtp_contribution
                "PAYTABLE" | "PAY TABLE" | "PAY_TABLE" | "COMBINATIONS" | "PAYS" => {
                    if cols.len() < 3 {
                        continue;
                    }
                    if cols[0].trim().to_lowercase() == "symbol_id"
                        || cols[0].trim().to_lowercase() == "symbol"
                    {
                        continue;
                    }
                    let symbol_id = match cols[0].trim().parse::<u32>() {
                        Ok(v) => v,
                        Err(_) => continue,
                    };
                    let count = match cols[1].trim().parse::<u8>() {
                        Ok(v) => v,
                        Err(_) => continue,
                    };
                    let payout = self.parse_f64(cols[2].trim(), "payout_multiplier", line_idx)?;
                    let rtp_contrib = cols
                        .get(3)
                        .and_then(|s| s.trim().parse::<f64>().ok())
                        .unwrap_or(0.0);
                    let hit_freq = cols
                        .get(4)
                        .and_then(|s| s.trim().parse::<f64>().ok())
                        .unwrap_or(0.0);

                    if doc.pay_combinations.len() >= self.limits.max_pay_combinations {
                        return Err(ParParseError::LimitExceeded(format!(
                            "Too many pay combinations (max {})",
                            self.limits.max_pay_combinations
                        )));
                    }

                    doc.pay_combinations.push(PayCombination {
                        symbol_id,
                        count,
                        payout_multiplier: payout,
                        rtp_contribution: rtp_contrib,
                        hit_frequency_per_1000: hit_freq,
                    });
                }

                // ── FEATURES section ──────────────────────────────────────────
                // Expected: feature_type, name, trigger_probability, avg_payout, rtp_contribution
                "FEATURES" | "FEATURE TRIGGERS" | "FEATURE_TRIGGERS" | "BONUS" => {
                    if cols.len() < 3 {
                        continue;
                    }
                    if cols[0].trim().to_lowercase() == "type"
                        || cols[0].trim().to_lowercase() == "feature_type"
                    {
                        continue;
                    }
                    let feature_type = ParFeatureType::from_str(cols[0].trim());
                    let name = cols.get(1).map(|s| s.trim().to_string()).unwrap_or_default();
                    let trigger_prob = self.parse_f64(
                        cols.get(2).map(|s| s.trim()).unwrap_or("0"),
                        "trigger_probability",
                        line_idx,
                    )?;
                    let avg_payout = cols
                        .get(3)
                        .and_then(|s| s.trim().parse::<f64>().ok())
                        .unwrap_or(0.0);
                    let rtp_contrib = cols
                        .get(4)
                        .and_then(|s| s.trim().parse::<f64>().ok())
                        .unwrap_or(0.0);

                    if doc.features.len() >= self.limits.max_features {
                        return Err(ParParseError::LimitExceeded(format!(
                            "Too many features (max {})",
                            self.limits.max_features
                        )));
                    }

                    doc.features.push(ParFeature {
                        feature_type,
                        name,
                        trigger_probability: trigger_prob,
                        avg_payout_multiplier: avg_payout,
                        rtp_contribution: rtp_contrib,
                        avg_duration_spins: 0.0,
                        retrigger_probability: 0.0,
                    });
                }

                // ── RTP BREAKDOWN section ─────────────────────────────────────
                "RTP" | "RTP BREAKDOWN" | "RTP_BREAKDOWN" => {
                    if cols.len() < 2 {
                        continue;
                    }
                    let key = cols[0].trim().to_lowercase();
                    let val = cols[1].trim();
                    match key.as_str() {
                        "base_game" | "base game" | "line wins" => {
                            let v = self.parse_f64(val, "base_game_rtp", line_idx)?;
                            doc.rtp_breakdown.base_game_rtp = if v > 1.0 { v / 100.0 } else { v };
                        }
                        "free_spins" | "free spins" | "bonus feature" => {
                            let v = self.parse_f64(val, "free_spins_rtp", line_idx)?;
                            doc.rtp_breakdown.free_spins_rtp = if v > 1.0 { v / 100.0 } else { v };
                        }
                        "bonus" | "pick bonus" => {
                            let v = self.parse_f64(val, "bonus_rtp", line_idx)?;
                            doc.rtp_breakdown.bonus_rtp = if v > 1.0 { v / 100.0 } else { v };
                        }
                        "jackpot" | "progressive" => {
                            let v = self.parse_f64(val, "jackpot_rtp", line_idx)?;
                            doc.rtp_breakdown.jackpot_rtp = if v > 1.0 { v / 100.0 } else { v };
                        }
                        "gamble" | "risk" => {
                            let v = self.parse_f64(val, "gamble_rtp", line_idx)?;
                            doc.rtp_breakdown.gamble_rtp = if v > 1.0 { v / 100.0 } else { v };
                        }
                        _ => {}
                    }
                }

                _ => {} // Unknown sections ignored
            }
        }

        // Require game name at minimum
        if doc.game_name.is_empty() && doc.game_id.is_empty() {
            return Err(ParParseError::MissingField(
                "game_name (and game_id) — no HEADER section found or no name,value pairs".to_string(),
            ));
        }

        // Auto-fill game_id from name if missing
        if doc.game_id.is_empty() {
            doc.game_id = doc
                .game_name
                .to_lowercase()
                .replace(' ', "_")
                .chars()
                .filter(|c| c.is_alphanumeric() || *c == '_')
                .collect();
        }

        Ok(doc)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Normalize
    // ─────────────────────────────────────────────────────────────────────────

    fn normalize(&self, doc: &mut ParDocument) {
        // RTP: ensure it's in percentage form (e.g. 96.5 not 0.965)
        if doc.rtp_target > 0.0 && doc.rtp_target < 1.0 {
            doc.rtp_target *= 100.0;
        }

        // Recompute hit frequency from dead_spin if only dead_spin is set
        if doc.hit_frequency == 0.0 && doc.dead_spin_frequency > 0.0 {
            doc.hit_frequency = 1.0 - doc.dead_spin_frequency;
        }
        if doc.dead_spin_frequency == 0.0 && doc.hit_frequency > 0.0 {
            doc.dead_spin_frequency = 1.0 - doc.hit_frequency;
        }

        // Recompute RTP breakdown total
        doc.rtp_breakdown.recompute_total();

        // Fill RTP breakdown from target if completely missing
        if doc.rtp_breakdown.total_rtp == 0.0 && doc.rtp_target > 0.0 {
            // Estimate: assume 70% base game, 30% features
            let rtp_frac = doc.rtp_target / 100.0;
            let feature_rtp: f64 = doc.features.iter().map(|f| f.rtp_contribution).sum();
            if feature_rtp > 0.0 {
                doc.rtp_breakdown.base_game_rtp = rtp_frac - feature_rtp;
                doc.rtp_breakdown.free_spins_rtp = feature_rtp;
            } else {
                doc.rtp_breakdown.base_game_rtp = rtp_frac * 0.70;
                doc.rtp_breakdown.free_spins_rtp = rtp_frac * 0.30;
            }
            doc.rtp_breakdown.recompute_total();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Security limits
    // ─────────────────────────────────────────────────────────────────────────

    fn apply_limits(&self, doc: &ParDocument) -> Result<(), ParParseError> {
        if doc.symbols.len() > self.limits.max_symbols {
            return Err(ParParseError::LimitExceeded(format!(
                "symbols: {} > {}",
                doc.symbols.len(),
                self.limits.max_symbols
            )));
        }
        if doc.pay_combinations.len() > self.limits.max_pay_combinations {
            return Err(ParParseError::LimitExceeded(format!(
                "pay_combinations: {} > {}",
                doc.pay_combinations.len(),
                self.limits.max_pay_combinations
            )));
        }
        if doc.features.len() > self.limits.max_features {
            return Err(ParParseError::LimitExceeded(format!(
                "features: {} > {}",
                doc.features.len(),
                self.limits.max_features
            )));
        }
        Ok(())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Parse helpers
    // ─────────────────────────────────────────────────────────────────────────

    fn parse_f64(&self, s: &str, field: &str, _line: usize) -> Result<f64, ParParseError> {
        // Handle percentage strings like "96.5%"
        let clean = s.trim_end_matches('%').trim();
        clean.parse::<f64>().map_err(|_| ParParseError::InvalidValue {
            field: field.to_string(),
            message: format!("Cannot parse '{}' as number", s),
        })
    }

    fn parse_u8(&self, s: &str, field: &str, _line: usize) -> Result<u8, ParParseError> {
        s.trim().parse::<u8>().map_err(|_| ParParseError::InvalidValue {
            field: field.to_string(),
            message: format!("Cannot parse '{}' as u8", s),
        })
    }

    fn parse_u16(&self, s: &str, field: &str, _line: usize) -> Result<u16, ParParseError> {
        s.trim().parse::<u16>().map_err(|_| ParParseError::InvalidValue {
            field: field.to_string(),
            message: format!("Cannot parse '{}' as u16", s),
        })
    }

    fn parse_u32(&self, s: &str, field: &str, _line: usize) -> Result<u32, ParParseError> {
        s.trim().parse::<u32>().map_err(|_| ParParseError::InvalidValue {
            field: field.to_string(),
            message: format!("Cannot parse '{}' as u32", s),
        })
    }

    fn parse_bool(s: &str) -> bool {
        matches!(
            s.to_lowercase().as_str(),
            "true" | "1" | "yes" | "y" | "wild" | "scatter"
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// T2.2: AUTO-CALIBRATE WIN TIER THRESHOLDS FROM PAR DISTRIBUTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Win tier calibration result (T2.2)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalibrationResult {
    /// The calibrated P5 regular win tier config
    pub regular_win_config: RegularWinConfig,
    /// Calibration diagnostics
    pub diagnostics: CalibrationDiagnostics,
}

/// Diagnostics from win tier calibration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalibrationDiagnostics {
    /// Total pay combinations analyzed
    pub combinations_analyzed: usize,
    /// Percentile boundaries used
    pub percentile_boundaries: [f64; 4],
    /// Multiplier at each boundary
    pub multiplier_at_boundaries: [f64; 4],
    /// RTP weight at each tier
    pub rtp_weight_per_tier: [f64; 5],
    /// Rollup durations assigned (ms)
    pub rollup_durations_ms: [u32; 5],
}

/// Auto-calibrate win tier thresholds from PAR RTP distribution.
///
/// **Algorithm (T2.2)**:
/// 1. Collect all (payout_multiplier, rtp_contribution) pairs
/// 2. Sort by payout_multiplier ascending
/// 3. Build cumulative RTP contribution array
/// 4. Place tier boundaries at RTP percentiles:
///    - WIN_1: 0–50th RTP percentile  (most frequent, smallest wins)
///    - WIN_2: 50–75th
///    - WIN_3: 75–90th
///    - WIN_4: 90–97th
///    - WIN_5: 97–100th (rarest, largest wins)
/// 5. Rollup duration proportional to RTP contribution weight
/// 6. Audio intensity proportional to RTP contribution
pub fn auto_calibrate_win_tiers(doc: &ParDocument) -> CalibrationResult {
    // Step 1 + 2: collect and sort pay combinations
    let mut combos: Vec<(f64, f64)> = doc
        .pay_combinations
        .iter()
        .filter(|c| c.payout_multiplier > 0.0)
        .map(|c| (c.payout_multiplier, c.rtp_contribution))
        .collect();

    // If no combinations with RTP data, use payout_multiplier alone
    let has_rtp = combos.iter().any(|(_, r)| *r > 0.0);
    if !has_rtp {
        // Fill synthetic RTP contributions: proportional to 1/multiplier (higher mult = rarer)
        let total: f64 = combos.iter().map(|(m, _)| 1.0 / m.max(0.01)).sum();
        combos = combos
            .iter()
            .map(|(m, _)| (*m, (1.0 / m.max(0.01)) / total.max(f64::EPSILON)))
            .collect();
    }

    combos.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    let total_rtp: f64 = combos.iter().map(|(_, r)| *r).sum::<f64>().max(f64::EPSILON);

    // Step 3: build cumulative RTP curve
    let mut cum_rtp = 0.0_f64;
    let cumulative: Vec<(f64, f64)> = combos
        .iter()
        .map(|(mult, rtp)| {
            cum_rtp += rtp;
            (*mult, cum_rtp / total_rtp)
        })
        .collect();

    // Step 4: find multiplier at each RTP percentile boundary
    let boundaries = [0.50_f64, 0.75, 0.90, 0.97];
    let mut mult_at = [0.0_f64; 4];
    for (b_idx, &target_pct) in boundaries.iter().enumerate() {
        mult_at[b_idx] = cumulative
            .iter()
            .find(|(_, cum)| *cum >= target_pct)
            .map(|(m, _)| *m)
            .unwrap_or(combos.last().map(|(m, _)| *m).unwrap_or(5.0));
    }

    // Ensure monotonically increasing boundaries (guard against degenerate distributions)
    for i in 1..4 {
        if mult_at[i] <= mult_at[i - 1] {
            mult_at[i] = mult_at[i - 1] * 1.5 + 1.0;
        }
    }
    // Ensure WIN_1 starts at 1.0 minimum
    if mult_at[0] < 1.0 {
        mult_at[0] = 1.0;
    }

    // Step 5: compute RTP weight per tier for rollup duration scaling
    let tier_rtp_weights = compute_tier_rtp_weights(&combos, &mult_at, total_rtp);

    // Step 6: rollup durations — start from base, scale slightly by RTP weight,
    // then enforce strict monotonic increase (higher tier = longer or equal rollup).
    // Base durations: WIN_1=500ms, WIN_5=5000ms (these are already monotonic)
    let base_durations = [500_u32, 1000, 2000, 3500, 5000];
    let rollup_durations: [u32; 5] = {
        let max_weight = tier_rtp_weights
            .iter()
            .cloned()
            .fold(f64::NEG_INFINITY, f64::max)
            .max(f64::EPSILON);
        // Compute raw (possibly non-monotonic due to variable weights)
        let raw: Vec<u32> = (0..5)
            .map(|i| {
                let scale = (tier_rtp_weights[i] / max_weight).sqrt().max(0.3);
                (base_durations[i] as f64 * scale) as u32
            })
            .collect();
        // Enforce monotonic non-decrease by taking max with previous + 50ms
        let mut result = [0u32; 5];
        result[0] = raw[0];
        for i in 1..5 {
            result[i] = raw[i].max(result[i - 1] + 50);
        }
        result
    };

    // Build WinTierConfig
    let tiers: Vec<RegularWinTier> = vec![
        // WIN_LOW: < 1x bet (sub-bet, no celebration)
        build_tier(-1, 0.0, 1.0, "WIN LOW", 200, 10),
        // WIN_EQUAL: = 1x bet (push)
        build_tier(0, 1.0, mult_at[0], "WIN EQUAL", 400, 12),
        // WIN_1 through WIN_5
        build_tier(1, mult_at[0], mult_at[1], "WIN 1", rollup_durations[0], 15),
        build_tier(2, mult_at[1], mult_at[2], "WIN 2", rollup_durations[1], 15),
        build_tier(3, mult_at[2], mult_at[3], "WIN 3", rollup_durations[2], 20),
        build_tier(4, mult_at[3], mult_at[3] * 3.0, "WIN 4", rollup_durations[3], 24),
        build_tier(5, mult_at[3] * 3.0, f64::MAX, "WIN 5", rollup_durations[4], 30),
    ];

    CalibrationResult {
        regular_win_config: RegularWinConfig {
            config_id: "par_calibrated".to_string(),
            name: "PAR Calibrated".to_string(),
            tiers,
        },
        diagnostics: CalibrationDiagnostics {
            combinations_analyzed: combos.len(),
            percentile_boundaries: boundaries,
            multiplier_at_boundaries: mult_at,
            rtp_weight_per_tier: tier_rtp_weights,
            rollup_durations_ms: rollup_durations,
        },
    }
}

fn compute_tier_rtp_weights(
    combos: &[(f64, f64)],
    boundaries: &[f64; 4],
    total_rtp: f64,
) -> [f64; 5] {
    let mut weights = [0.0_f64; 5];
    for (mult, rtp) in combos {
        let tier_idx = if *mult < boundaries[0] {
            0
        } else if *mult < boundaries[1] {
            1
        } else if *mult < boundaries[2] {
            2
        } else if *mult < boundaries[3] {
            3
        } else {
            4
        };
        weights[tier_idx] += rtp / total_rtp;
    }
    weights
}

fn build_tier(
    id: i32,
    from: f64,
    to: f64,
    label: &str,
    rollup_ms: u32,
    tick_rate: u32,
) -> RegularWinTier {
    RegularWinTier {
        tier_id: id,
        from_multiplier: from,
        to_multiplier: to,
        display_label: label.to_string(),
        rollup_duration_ms: rollup_ms,
        rollup_tick_rate: tick_rate,
        particle_burst_count: (rollup_ms / 200).min(25),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_json_par() -> &'static str {
        r#"{
            "game_name": "Fortune Dragon",
            "game_id": "fortune_dragon",
            "rtp_target": 96.50,
            "volatility": "HIGH",
            "reels": 5,
            "rows": 3,
            "paylines": 20,
            "hit_frequency": 0.28,
            "pay_combinations": [
                {"symbol_id": 1, "count": 5, "payout_multiplier": 500.0, "rtp_contribution": 0.05},
                {"symbol_id": 1, "count": 4, "payout_multiplier": 100.0, "rtp_contribution": 0.08},
                {"symbol_id": 1, "count": 3, "payout_multiplier": 20.0,  "rtp_contribution": 0.12},
                {"symbol_id": 2, "count": 5, "payout_multiplier": 250.0, "rtp_contribution": 0.06},
                {"symbol_id": 2, "count": 4, "payout_multiplier": 50.0,  "rtp_contribution": 0.09},
                {"symbol_id": 2, "count": 3, "payout_multiplier": 10.0,  "rtp_contribution": 0.15},
                {"symbol_id": 3, "count": 5, "payout_multiplier": 100.0, "rtp_contribution": 0.04},
                {"symbol_id": 3, "count": 4, "payout_multiplier": 25.0,  "rtp_contribution": 0.07},
                {"symbol_id": 3, "count": 3, "payout_multiplier": 5.0,   "rtp_contribution": 0.20},
                {"symbol_id": 4, "count": 5, "payout_multiplier": 50.0,  "rtp_contribution": 0.03},
                {"symbol_id": 4, "count": 3, "payout_multiplier": 2.0,   "rtp_contribution": 0.11}
            ],
            "features": [
                {"feature_type": "FREE_SPINS", "name": "Dragon Spins", "trigger_probability": 0.00667, "avg_payout_multiplier": 30.0, "rtp_contribution": 0.0500}
            ],
            "symbols": [
                {"id": 1, "name": "Dragon", "is_wild": false, "is_scatter": false, "reel_weights": [2,2,2,2,2]},
                {"id": 2, "name": "Phoenix", "is_wild": false, "is_scatter": false, "reel_weights": [3,3,3,3,3]},
                {"id": 3, "name": "Koi", "is_wild": false, "is_scatter": false, "reel_weights": [4,4,4,4,4]},
                {"id": 4, "name": "Coin", "is_wild": false, "is_scatter": false, "reel_weights": [5,5,5,5,5]},
                {"id": 10, "name": "Wild", "is_wild": true, "is_scatter": false, "reel_weights": [1,1,1,1,1]},
                {"id": 11, "name": "Scatter", "is_wild": false, "is_scatter": true, "reel_weights": [1,1,1,1,1]}
            ]
        }"#
    }

    fn minimal_csv_par() -> &'static str {
        "=== HEADER ===\n\
         game_name,Fortune Dragon CSV\n\
         game_id,fortune_dragon_csv\n\
         rtp,96.50\n\
         volatility,high\n\
         reels,5\n\
         rows,3\n\
         paylines,20\n\
         hit_frequency,0.28\n\
         === SYMBOLS ===\n\
         id,name,is_wild,is_scatter,reel_1,reel_2,reel_3,reel_4,reel_5\n\
         1,Dragon,false,false,2,2,2,2,2\n\
         10,Wild,true,false,1,1,1,1,1\n\
         11,Scatter,false,true,1,1,1,1,1\n\
         === PAYTABLE ===\n\
         symbol_id,count,payout_multiplier,rtp_contribution\n\
         1,5,500.0,0.05\n\
         1,3,20.0,0.12\n\
         === FEATURES ===\n\
         type,name,trigger_probability,avg_payout,rtp_contribution\n\
         free_spins,Dragon Spins,0.00667,30.0,0.05\n"
    }

    #[test]
    fn test_parse_json_basic() {
        let parser = ParParser::new();
        let doc = parser.parse_json(minimal_json_par()).unwrap();
        assert_eq!(doc.game_name, "Fortune Dragon");
        assert_eq!(doc.game_id, "fortune_dragon");
        assert!((doc.rtp_target - 96.50).abs() < 0.01);
        assert_eq!(doc.volatility, ParVolatility::High);
        assert_eq!(doc.reels, 5);
        assert_eq!(doc.rows, 3);
        assert_eq!(doc.paylines, 20);
        assert_eq!(doc.symbols.len(), 6);
        assert_eq!(doc.pay_combinations.len(), 11);
        assert_eq!(doc.features.len(), 1);
    }

    #[test]
    fn test_parse_csv_basic() {
        let parser = ParParser::new();
        let doc = parser.parse_csv(minimal_csv_par()).unwrap();
        assert_eq!(doc.game_name, "Fortune Dragon CSV");
        assert_eq!(doc.reels, 5);
        assert_eq!(doc.symbols.len(), 3);
        assert_eq!(doc.pay_combinations.len(), 2);
        assert_eq!(doc.features.len(), 1);
        assert!(doc.symbols[1].is_wild);
        assert!(doc.symbols[2].is_scatter);
    }

    #[test]
    fn test_auto_detect_json() {
        let parser = ParParser::new();
        let doc = parser.parse_auto(minimal_json_par()).unwrap();
        assert_eq!(doc.source_format, "json");
    }

    #[test]
    fn test_auto_detect_csv() {
        let parser = ParParser::new();
        let doc = parser.parse_auto(minimal_csv_par()).unwrap();
        assert!(doc.source_format == "csv" || doc.source_format == "xlsx_csv");
    }

    #[test]
    fn test_validate_clean_par() {
        let parser = ParParser::new();
        let doc = parser.parse_json(minimal_json_par()).unwrap();
        let report = parser.validate(&doc);
        // Should have no errors
        assert_eq!(report.errors().count(), 0, "Errors: {:?}", report.findings);
        assert!(report.valid);
    }

    #[test]
    fn test_validate_rtp_out_of_range() {
        let parser = ParParser::new();
        let json = r#"{
            "game_name": "Bad Game",
            "game_id": "bad",
            "rtp_target": 101.0,
            "volatility": "MEDIUM",
            "reels": 5,
            "rows": 3
        }"#;
        let doc = parser.parse_json(json).unwrap();
        let report = parser.validate(&doc);
        assert!(!report.valid);
        assert!(report.errors().any(|e| e.field == "rtp_target"));
    }

    #[test]
    fn test_validate_invalid_reels() {
        let parser = ParParser::new();
        let json = r#"{
            "game_name": "Bad Reels",
            "game_id": "bad_reels",
            "rtp_target": 96.0,
            "volatility": "MEDIUM",
            "reels": 1,
            "rows": 3
        }"#;
        let doc = parser.parse_json(json).unwrap();
        let report = parser.validate(&doc);
        assert!(!report.valid);
        assert!(report.errors().any(|e| e.field == "reels"));
    }

    #[test]
    fn test_auto_calibrate_win_tiers() {
        let parser = ParParser::new();
        let doc = parser.parse_json(minimal_json_par()).unwrap();
        let result = auto_calibrate_win_tiers(&doc);

        let tiers = &result.regular_win_config.tiers;
        assert!(!tiers.is_empty(), "No tiers calibrated");
        assert_eq!(result.regular_win_config.config_id, "par_calibrated");

        // Check tier_ids
        let ids: Vec<i32> = tiers.iter().map(|t| t.tier_id).collect();
        assert!(ids.contains(&-1), "Missing WIN_LOW");
        assert!(ids.contains(&1), "Missing WIN_1");
        assert!(ids.contains(&5), "Missing WIN_5");

        // Each tier boundary should be monotonically increasing
        let regular_tiers: Vec<&RegularWinTier> =
            tiers.iter().filter(|t| t.tier_id > 0).collect();
        for window in regular_tiers.windows(2) {
            assert!(
                window[1].from_multiplier >= window[0].from_multiplier,
                "Tier boundaries not monotonic: {} -> {}",
                window[0].from_multiplier,
                window[1].from_multiplier
            );
        }

        // Higher tiers should have longer or equal rollup durations
        let rollup: Vec<u32> = regular_tiers.iter().map(|t| t.rollup_duration_ms).collect();
        for window in rollup.windows(2) {
            assert!(
                window[1] >= window[0],
                "Rollup durations not non-decreasing: {} -> {}",
                window[0],
                window[1]
            );
        }

        println!("Calibration diagnostics: {:?}", result.diagnostics);
    }

    #[test]
    fn test_auto_calibrate_no_rtp_data() {
        // Combos with no RTP data — should fall back to synthetic weights
        let json = r#"{
            "game_name": "Simple Game",
            "game_id": "simple",
            "rtp_target": 95.0,
            "volatility": "MEDIUM",
            "reels": 5,
            "rows": 3,
            "pay_combinations": [
                {"symbol_id": 1, "count": 5, "payout_multiplier": 200.0, "rtp_contribution": 0.0},
                {"symbol_id": 1, "count": 3, "payout_multiplier": 10.0, "rtp_contribution": 0.0},
                {"symbol_id": 2, "count": 5, "payout_multiplier": 100.0, "rtp_contribution": 0.0},
                {"symbol_id": 2, "count": 3, "payout_multiplier": 5.0, "rtp_contribution": 0.0}
            ]
        }"#;
        let parser = ParParser::new();
        let doc = parser.parse_json(json).unwrap();
        let result = auto_calibrate_win_tiers(&doc);
        assert!(!result.regular_win_config.tiers.is_empty());
    }

    #[test]
    fn test_rtp_normalization_fraction_form() {
        // PAR files sometimes express RTP as 0.965 instead of 96.5
        let json = r#"{
            "game_name": "Fraction RTP",
            "game_id": "frac",
            "rtp_target": 0.965,
            "volatility": "HIGH",
            "reels": 5,
            "rows": 3
        }"#;
        let parser = ParParser::new();
        let doc = parser.parse_json(json).unwrap();
        assert!((doc.rtp_target - 96.5).abs() < 0.01, "RTP not normalized: {}", doc.rtp_target);
    }

    #[test]
    fn test_par_volatility_from_str() {
        assert_eq!(ParVolatility::from_str("high"), ParVolatility::High);
        assert_eq!(ParVolatility::from_str("VERY_HIGH"), ParVolatility::VeryHigh);
        assert_eq!(ParVolatility::from_str("vh"), ParVolatility::VeryHigh);
        assert_eq!(ParVolatility::from_str("l"), ParVolatility::Low);
        assert_eq!(ParVolatility::from_str("extreme"), ParVolatility::Extreme);
    }

    #[test]
    fn test_feature_type_from_str() {
        assert_eq!(
            ParFeatureType::from_str("free_spins"),
            ParFeatureType::FreeSpins
        );
        assert_eq!(
            ParFeatureType::from_str("Hold And Win"),
            ParFeatureType::HoldAndWin
        );
        assert_eq!(
            ParFeatureType::from_str("progressive"),
            ParFeatureType::Jackpot
        );
    }

    #[test]
    fn test_csv_rtp_percentage_normalization() {
        let csv = "=== HEADER ===\n\
                   game_name,Test Game\n\
                   game_id,test_game\n\
                   rtp,96.5%\n\
                   volatility,medium\n\
                   reels,5\n\
                   rows,3\n";
        let parser = ParParser::new();
        let doc = parser.parse_csv(csv).unwrap();
        assert!((doc.rtp_target - 96.5).abs() < 0.01, "RTP: {}", doc.rtp_target);
    }
}
