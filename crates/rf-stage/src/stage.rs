//! Stage — The core enum defining all canonical game phases
//!
//! A Stage is NOT an animation, NOT an engine event.
//! A Stage is the SEMANTIC MEANING of a moment in the game flow.

use serde::{Deserialize, Serialize};

use crate::taxonomy::{BigWinTier, BonusChoiceType, FeatureType, GambleResult, JackpotTier};

/// Canonical game stage — the universal language of slot game flow
///
/// Every slot game, regardless of engine, maps to these stages.
/// FluxForge audio responds to stages, never to raw engine events.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Stage {
    // ═══════════════════════════════════════════════════════════════════════
    // SPIN LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════
    /// Spin button pressed, spin initiated
    SpinStart,

    /// Shared spin loop audio — triggered once on spin start, loops until SPIN_END
    /// This is the single looping reel spin audio (not per-reel)
    ReelSpinLoop,

    /// Reel is spinning (not yet stopped)
    ReelSpinning {
        /// Which reel (0-indexed)
        reel_index: u8,
    },

    /// P0.1: Single reel starts spinning (for per-reel audio control)
    /// Used to trigger individual spin loop for each reel
    ReelSpinningStart {
        /// Which reel (0-indexed)
        reel_index: u8,
    },

    /// P0.1: Single reel stops spinning (triggers fade-out of spin loop)
    /// Emitted at same time as ReelStop to fade out the spin loop audio
    ReelSpinningStop {
        /// Which reel (0-indexed)
        reel_index: u8,
    },

    /// Reel has stopped, showing final symbols
    ReelStop {
        /// Which reel stopped (0-indexed)
        reel_index: u8,
        /// Symbols on this reel (top to bottom)
        #[serde(default)]
        symbols: Vec<u32>,
    },

    /// All reels stopped, wins being evaluated
    EvaluateWins,

    /// Spin complete, ready for next spin
    SpinEnd,

    // ═══════════════════════════════════════════════════════════════════════
    // ANTICIPATION
    // ═══════════════════════════════════════════════════════════════════════
    /// Anticipation triggered (slow spin, tension build)
    AnticipationOn {
        /// Which reel is in anticipation
        reel_index: u8,
        /// Reason for anticipation (e.g., "scatter", "bonus")
        #[serde(default)]
        reason: Option<String>,
    },

    /// Anticipation ended
    AnticipationOff {
        /// Which reel
        reel_index: u8,
    },

    /// Per-reel anticipation tension layer (escalating audio)
    /// Audio intensity increases with each reel: L1 → L2 → L3 → L4
    AnticipationTensionLayer {
        /// Which reel (0-indexed)
        reel_index: u8,
        /// Tension layer level (1-4)
        tension_level: u8,
        /// Reason for anticipation (scatter, bonus, wild, jackpot)
        #[serde(default)]
        reason: Option<String>,
        /// Progress through this reel's anticipation (0.0 - 1.0)
        #[serde(default)]
        progress: f32,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // WIN LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════
    /// Win celebration starting
    WinPresent {
        /// Total win amount
        #[serde(default)]
        win_amount: f64,
        /// Number of winning lines
        #[serde(default)]
        line_count: u8,
    },

    /// Individual win line being highlighted
    WinLineShow {
        /// Which line
        line_index: u8,
        /// Win amount for this line
        #[serde(default)]
        line_amount: f64,
    },

    /// Win counter (rollup) starting
    RollupStart {
        /// Target amount to count to
        target_amount: f64,
        /// Starting amount (usually 0 or previous balance)
        #[serde(default)]
        start_amount: f64,
    },

    /// Rollup tick (for granular audio)
    RollupTick {
        /// Current displayed amount
        current_amount: f64,
        /// Progress (0.0 - 1.0)
        progress: f64,
    },

    /// Rollup complete
    RollupEnd {
        /// Final amount
        final_amount: f64,
    },

    /// Big win tier reached
    BigWinTier {
        /// Which tier
        tier: BigWinTier,
        /// Win amount
        #[serde(default)]
        amount: f64,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // FEATURE LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════
    /// Entering a feature (free spins, bonus, etc.)
    FeatureEnter {
        /// Type of feature
        feature_type: FeatureType,
        /// Total steps/spins in feature
        #[serde(default)]
        total_steps: Option<u32>,
        /// Initial multiplier
        #[serde(default)]
        multiplier: f64,
    },

    /// Feature step (e.g., one free spin)
    FeatureStep {
        /// Current step index (0-based)
        step_index: u32,
        /// Remaining steps
        #[serde(default)]
        steps_remaining: Option<u32>,
        /// Current multiplier
        #[serde(default)]
        current_multiplier: f64,
    },

    /// Feature retrigger (more spins added)
    FeatureRetrigger {
        /// Additional steps added
        additional_steps: u32,
        /// New total
        #[serde(default)]
        new_total: Option<u32>,
    },

    /// Exiting feature
    FeatureExit {
        /// Total win from feature
        #[serde(default)]
        total_win: f64,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // CASCADE / TUMBLE
    // ═══════════════════════════════════════════════════════════════════════
    /// Cascade/tumble sequence starting
    CascadeStart,

    /// Individual cascade step (symbols falling)
    CascadeStep {
        /// Cascade step number (0-based)
        step_index: u32,
        /// Multiplier for this cascade
        #[serde(default)]
        multiplier: f64,
    },

    /// Cascade sequence complete
    CascadeEnd {
        /// Total cascade steps
        total_steps: u32,
        /// Total win from cascade
        #[serde(default)]
        total_win: f64,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // BONUS / PICK GAMES
    // ═══════════════════════════════════════════════════════════════════════
    /// Entering bonus/pick game
    BonusEnter {
        /// Bonus game name/type
        #[serde(default)]
        bonus_name: Option<String>,
    },

    /// Player making a choice
    BonusChoice {
        /// Type of choice
        choice_type: BonusChoiceType,
        /// Number of options
        #[serde(default)]
        option_count: u8,
    },

    /// Bonus item revealed
    BonusReveal {
        /// Revealed value
        #[serde(default)]
        revealed_value: f64,
        /// Is this the end (e.g., revealed "collect")?
        #[serde(default)]
        is_terminal: bool,
    },

    /// Exiting bonus game
    BonusExit {
        /// Total bonus win
        #[serde(default)]
        total_win: f64,
    },

    /// Bonus game starting (pick/wheel/etc)
    BonusStart {
        /// Type of bonus game
        bonus_type: String,
        /// Total picks available
        #[serde(default)]
        total_picks: u32,
    },

    /// Prize revealed in pick bonus
    BonusPrizeReveal {
        /// Type of prize (coins, multiplier, jackpot, etc)
        prize_type: String,
        /// Prize value
        #[serde(default)]
        prize_value: f64,
    },

    /// Bonus game complete (pick/wheel/etc)
    BonusComplete {
        /// Total win from bonus
        #[serde(default)]
        total_win: f64,
        /// Picks used
        #[serde(default)]
        picks_used: u32,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // GAMBLE / RISK
    // ═══════════════════════════════════════════════════════════════════════
    /// Gamble feature starting
    GambleStart {
        /// Amount at stake
        stake_amount: f64,
    },

    /// Player making gamble choice
    GambleChoice {
        /// Type of choice
        choice_type: BonusChoiceType,
    },

    /// Gamble result
    GambleResultStage {
        /// Win/Lose/Draw
        result: GambleResult,
        /// New amount (if won) or 0 (if lost)
        #[serde(default)]
        new_amount: f64,
    },

    /// Gamble feature ending
    GambleEnd {
        /// Final collected amount
        collected_amount: f64,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // JACKPOT
    // ═══════════════════════════════════════════════════════════════════════
    /// Jackpot triggered
    JackpotTrigger {
        /// Which jackpot tier
        tier: JackpotTier,
    },

    /// Jackpot presentation/celebration
    JackpotPresent {
        /// Jackpot amount
        amount: f64,
        /// Tier
        tier: JackpotTier,
    },

    /// P1.5: Jackpot buildup - rising tension before reveal
    JackpotBuildup {
        /// Which jackpot tier
        tier: JackpotTier,
    },

    /// P1.5: Jackpot tier reveal - "GRAND!" announcement
    JackpotReveal {
        /// Jackpot amount
        amount: f64,
        /// Tier being revealed
        tier: JackpotTier,
    },

    /// P1.5: Jackpot celebration loop - plays until dismissed
    JackpotCelebration {
        /// Jackpot amount
        amount: f64,
        /// Tier being celebrated
        tier: JackpotTier,
    },

    /// Jackpot celebration complete
    JackpotEnd,

    // ═══════════════════════════════════════════════════════════════════════
    // UI / IDLE
    // ═══════════════════════════════════════════════════════════════════════
    /// Game entering idle state
    IdleStart,

    /// Idle loop point (for looping ambient)
    IdleLoop,

    /// Menu/settings opened
    MenuOpen {
        /// Which menu
        #[serde(default)]
        menu_name: Option<String>,
    },

    /// Menu/settings closed
    MenuClose,

    /// Autoplay started
    AutoplayStart {
        /// Number of spins
        #[serde(default)]
        spin_count: Option<u32>,
    },

    /// Autoplay stopped
    AutoplayStop {
        /// Reason for stopping
        #[serde(default)]
        reason: Option<String>,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // SPECIAL
    // ═══════════════════════════════════════════════════════════════════════
    /// Symbol transformation/morph
    SymbolTransform {
        /// Reel index
        reel_index: u8,
        /// Row index
        row_index: u8,
        /// From symbol ID
        #[serde(default)]
        from_symbol: Option<u32>,
        /// To symbol ID
        to_symbol: u32,
    },

    /// Wild expansion
    WildExpand {
        /// Reel index
        reel_index: u8,
        /// Direction (up, down, both)
        #[serde(default)]
        direction: Option<String>,
    },

    /// Multiplier change
    MultiplierChange {
        /// New multiplier value
        new_value: f64,
        /// Previous value
        #[serde(default)]
        old_value: Option<f64>,
    },

    // ═══════════════════════════════════════════════════════════════════════
    // P0.13-P0.17: ADDITIONAL STAGES
    // ═══════════════════════════════════════════════════════════════════════
    /// P0.13: Near miss — close to big win but didn't quite make it
    NearMiss {
        /// Which reel had the near miss
        #[serde(default)]
        reel_index: Option<u8>,
        /// What was almost achieved (e.g., "scatter", "bonus", "jackpot")
        #[serde(default)]
        reason: Option<String>,
        /// How close (0.0-1.0, higher = closer)
        #[serde(default)]
        proximity: f64,
    },

    /// P0.15: Symbol upgrade — symbol transforms to higher-paying version
    SymbolUpgrade {
        /// Reel index
        reel_index: u8,
        /// Row index
        row_index: u8,
        /// Original symbol ID
        #[serde(default)]
        from_symbol: Option<u32>,
        /// Upgraded symbol ID
        to_symbol: u32,
        /// Upgrade tier (1=one step, 2=two steps, etc.)
        #[serde(default)]
        upgrade_tier: u8,
    },

    /// P0.16: Mystery symbol reveal — mystery symbol shows its true form
    MysteryReveal {
        /// Number of mystery symbols being revealed
        mystery_count: u8,
        /// Symbol ID being revealed
        revealed_symbol: u32,
        /// Whether all mysteries reveal at once
        #[serde(default)]
        simultaneous: bool,
    },

    /// P0.17: Multiplier apply — when a multiplier is actually applied to a win
    MultiplierApply {
        /// Multiplier value being applied
        multiplier: f64,
        /// Win amount before multiplier
        base_amount: f64,
        /// Win amount after multiplier
        #[serde(default)]
        final_amount: f64,
    },

    /// Custom stage (engine-specific, adapter should document)
    Custom {
        /// Custom stage name
        name: String,
        /// Numeric ID
        #[serde(default)]
        id: u32,
    },
}

impl Stage {
    /// Get the stage category for grouping
    pub fn category(&self) -> StageCategory {
        match self {
            Stage::SpinStart
            | Stage::ReelSpinLoop
            | Stage::ReelSpinning { .. }
            | Stage::ReelSpinningStart { .. }  // P0.1
            | Stage::ReelSpinningStop { .. }   // P0.1
            | Stage::ReelStop { .. }
            | Stage::EvaluateWins
            | Stage::SpinEnd => StageCategory::SpinLifecycle,

            Stage::AnticipationOn { .. }
            | Stage::AnticipationOff { .. }
            | Stage::AnticipationTensionLayer { .. } => StageCategory::Anticipation,

            Stage::WinPresent { .. }
            | Stage::WinLineShow { .. }
            | Stage::RollupStart { .. }
            | Stage::RollupTick { .. }
            | Stage::RollupEnd { .. }
            | Stage::BigWinTier { .. } => StageCategory::WinLifecycle,

            Stage::FeatureEnter { .. }
            | Stage::FeatureStep { .. }
            | Stage::FeatureRetrigger { .. }
            | Stage::FeatureExit { .. } => StageCategory::Feature,

            Stage::CascadeStart | Stage::CascadeStep { .. } | Stage::CascadeEnd { .. } => {
                StageCategory::Cascade
            }

            Stage::BonusEnter { .. }
            | Stage::BonusChoice { .. }
            | Stage::BonusReveal { .. }
            | Stage::BonusExit { .. }
            | Stage::BonusStart { .. }
            | Stage::BonusPrizeReveal { .. }
            | Stage::BonusComplete { .. } => StageCategory::Bonus,

            Stage::GambleStart { .. }
            | Stage::GambleChoice { .. }
            | Stage::GambleResultStage { .. }
            | Stage::GambleEnd { .. } => StageCategory::Gamble,

            Stage::JackpotTrigger { .. }
            | Stage::JackpotPresent { .. }
            | Stage::JackpotBuildup { .. }      // P1.5
            | Stage::JackpotReveal { .. }       // P1.5
            | Stage::JackpotCelebration { .. }  // P1.5
            | Stage::JackpotEnd => StageCategory::Jackpot,

            Stage::IdleStart
            | Stage::IdleLoop
            | Stage::MenuOpen { .. }
            | Stage::MenuClose
            | Stage::AutoplayStart { .. }
            | Stage::AutoplayStop { .. } => StageCategory::UI,

            Stage::SymbolTransform { .. }
            | Stage::WildExpand { .. }
            | Stage::MultiplierChange { .. }
            | Stage::NearMiss { .. }       // P0.13
            | Stage::SymbolUpgrade { .. }  // P0.15
            | Stage::MysteryReveal { .. }  // P0.16
            | Stage::MultiplierApply { .. } // P0.17
            | Stage::Custom { .. } => StageCategory::Special,
        }
    }

    /// Get a simple string name for this stage type
    pub fn type_name(&self) -> &'static str {
        match self {
            Stage::SpinStart => "spin_start",
            Stage::ReelSpinLoop => "reel_spin_loop",
            Stage::ReelSpinning { .. } => "reel_spinning",
            Stage::ReelSpinningStart { .. } => "reel_spinning_start", // P0.1
            Stage::ReelSpinningStop { .. } => "reel_spinning_stop",   // P0.1
            Stage::ReelStop { .. } => "reel_stop",
            Stage::EvaluateWins => "evaluate_wins",
            Stage::SpinEnd => "spin_end",
            Stage::AnticipationOn { .. } => "anticipation_on",
            Stage::AnticipationOff { .. } => "anticipation_off",
            Stage::AnticipationTensionLayer { .. } => "anticipation_tension_layer",
            Stage::WinPresent { .. } => "win_present",
            Stage::WinLineShow { .. } => "win_line_show",
            Stage::RollupStart { .. } => "rollup_start",
            Stage::RollupTick { .. } => "rollup_tick",
            Stage::RollupEnd { .. } => "rollup_end",
            Stage::BigWinTier { .. } => "bigwin_tier",
            Stage::FeatureEnter { .. } => "feature_enter",
            Stage::FeatureStep { .. } => "feature_step",
            Stage::FeatureRetrigger { .. } => "feature_retrigger",
            Stage::FeatureExit { .. } => "feature_exit",
            Stage::CascadeStart => "cascade_start",
            Stage::CascadeStep { .. } => "cascade_step",
            Stage::CascadeEnd { .. } => "cascade_end",
            Stage::BonusEnter { .. } => "bonus_enter",
            Stage::BonusChoice { .. } => "bonus_choice",
            Stage::BonusReveal { .. } => "bonus_reveal",
            Stage::BonusExit { .. } => "bonus_exit",
            Stage::BonusStart { .. } => "bonus_start",
            Stage::BonusPrizeReveal { .. } => "bonus_prize_reveal",
            Stage::BonusComplete { .. } => "bonus_complete",
            Stage::GambleStart { .. } => "gamble_start",
            Stage::GambleChoice { .. } => "gamble_choice",
            Stage::GambleResultStage { .. } => "gamble_result",
            Stage::GambleEnd { .. } => "gamble_end",
            Stage::JackpotTrigger { .. } => "jackpot_trigger",
            Stage::JackpotPresent { .. } => "jackpot_present",
            Stage::JackpotBuildup { .. } => "jackpot_buildup",
            Stage::JackpotReveal { .. } => "jackpot_reveal",
            Stage::JackpotCelebration { .. } => "jackpot_celebration",
            Stage::JackpotEnd => "jackpot_end",
            Stage::IdleStart => "idle_start",
            Stage::IdleLoop => "idle_loop",
            Stage::MenuOpen { .. } => "menu_open",
            Stage::MenuClose => "menu_close",
            Stage::AutoplayStart { .. } => "autoplay_start",
            Stage::AutoplayStop { .. } => "autoplay_stop",
            Stage::SymbolTransform { .. } => "symbol_transform",
            Stage::WildExpand { .. } => "wild_expand",
            Stage::MultiplierChange { .. } => "multiplier_change",
            Stage::NearMiss { .. } => "near_miss", // P0.13
            Stage::SymbolUpgrade { .. } => "symbol_upgrade", // P0.15
            Stage::MysteryReveal { .. } => "mystery_reveal", // P0.16
            Stage::MultiplierApply { .. } => "multiplier_apply", // P0.17
            Stage::Custom { .. } => "custom",
        }
    }

    /// Check if this is a looping stage (audio should loop)
    pub fn is_looping(&self) -> bool {
        matches!(
            self,
            Stage::ReelSpinLoop  // Shared spin loop for all reels
                | Stage::ReelSpinning { .. }
                | Stage::ReelSpinningStart { .. } // P0.1: Per-reel spin loop
                | Stage::AnticipationOn { .. }
                | Stage::AnticipationTensionLayer { .. } // Per-reel tension layer loops
                | Stage::RollupTick { .. }
                | Stage::IdleLoop
                | Stage::JackpotCelebration { .. } // P1.5: Celebration loops until dismissed
        )
    }

    /// Check if this stage should duck music
    pub fn should_duck_music(&self) -> bool {
        matches!(
            self,
            Stage::BigWinTier { .. }
                | Stage::JackpotTrigger { .. }
                | Stage::JackpotPresent { .. }
                | Stage::JackpotBuildup { .. }    // P1.5: Duck during buildup
                | Stage::JackpotReveal { .. }     // P1.5: Duck during reveal
                | Stage::JackpotCelebration { .. } // P1.5: Duck during celebration
                | Stage::FeatureEnter { .. }
        )
    }

    /// Get all valid stage type names for validation
    pub fn all_type_names() -> &'static [&'static str] {
        &[
            "spin_start",
            "reel_spin_loop",
            "reel_spinning",
            "reel_spinning_start", // P0.1
            "reel_spinning_stop",  // P0.1
            "reel_stop",
            "evaluate_wins",
            "spin_end",
            "anticipation_on",
            "anticipation_off",
            "anticipation_tension_layer",
            "win_present",
            "win_line_show",
            "rollup_start",
            "rollup_tick",
            "rollup_end",
            "bigwin_tier",
            "feature_enter",
            "feature_step",
            "feature_retrigger",
            "feature_exit",
            "cascade_start",
            "cascade_step",
            "cascade_end",
            "bonus_enter",
            "bonus_choice",
            "bonus_reveal",
            "bonus_exit",
            "gamble_start",
            "gamble_choice",
            "gamble_result",
            "gamble_end",
            "jackpot_trigger",
            "jackpot_present",
            "jackpot_buildup",     // P1.5
            "jackpot_reveal",      // P1.5
            "jackpot_celebration", // P1.5
            "jackpot_end",
            "idle_start",
            "idle_loop",
            "menu_open",
            "menu_close",
            "autoplay_start",
            "autoplay_stop",
            "symbol_transform",
            "wild_expand",
            "multiplier_change",
            "near_miss",        // P0.13
            "symbol_upgrade",   // P0.15
            "mystery_reveal",   // P0.16
            "multiplier_apply", // P0.17
            "custom",
        ]
    }

    /// Check if a type name is valid
    pub fn is_valid_type_name(name: &str) -> bool {
        Self::all_type_names().contains(&name.to_lowercase().as_str())
    }

    /// Create a Stage from type name with default values
    /// Returns None for invalid type names
    /// For stages with required fields, use serde deserialization instead
    pub fn from_type_name(
        name: &str,
        data: &std::collections::HashMap<String, serde_json::Value>,
    ) -> Option<Self> {
        let name_lower = name.to_lowercase();

        // Helper to extract u8 value
        let get_u8 = |key: &str| -> u8 {
            data.get(key)
                .and_then(|v| v.as_u64())
                .map(|v| v as u8)
                .unwrap_or(0)
        };

        // Helper to extract f64 value
        let get_f64 = |key: &str| -> f64 { data.get(key).and_then(|v| v.as_f64()).unwrap_or(0.0) };

        // Helper to extract optional string
        let get_string = |key: &str| -> Option<String> {
            data.get(key)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        };

        match name_lower.as_str() {
            "spin_start" => Some(Stage::SpinStart),
            "reel_spin_loop" => Some(Stage::ReelSpinLoop),
            "reel_spinning" => Some(Stage::ReelSpinning {
                reel_index: get_u8("reel_index"),
            }),
            // P0.1: Per-reel spin start/stop
            "reel_spinning_start" => Some(Stage::ReelSpinningStart {
                reel_index: get_u8("reel_index"),
            }),
            "reel_spinning_stop" => Some(Stage::ReelSpinningStop {
                reel_index: get_u8("reel_index"),
            }),
            "reel_stop" => Some(Stage::ReelStop {
                reel_index: get_u8("reel_index"),
                symbols: Vec::new(),
            }),
            "evaluate_wins" => Some(Stage::EvaluateWins),
            "spin_end" => Some(Stage::SpinEnd),
            "anticipation_on" => Some(Stage::AnticipationOn {
                reel_index: get_u8("reel_index"),
                reason: get_string("reason"),
            }),
            "anticipation_off" => Some(Stage::AnticipationOff {
                reel_index: get_u8("reel_index"),
            }),
            "anticipation_tension_layer" => Some(Stage::AnticipationTensionLayer {
                reel_index: get_u8("reel_index"),
                tension_level: get_u8("tension_level").max(1).min(4),
                reason: get_string("reason"),
                progress: data.get("progress").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32,
            }),
            "win_present" => Some(Stage::WinPresent {
                win_amount: get_f64("win_amount"),
                line_count: get_u8("line_count"),
            }),
            "win_line_show" => Some(Stage::WinLineShow {
                line_index: get_u8("line_index"),
                line_amount: get_f64("line_amount"),
            }),
            "rollup_start" => Some(Stage::RollupStart {
                target_amount: get_f64("target_amount"),
                start_amount: get_f64("start_amount"),
            }),
            "rollup_tick" => Some(Stage::RollupTick {
                current_amount: get_f64("current_amount"),
                progress: get_f64("progress"),
            }),
            "rollup_end" => Some(Stage::RollupEnd {
                final_amount: get_f64("final_amount"),
            }),
            "bigwin_tier" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "win" => crate::taxonomy::BigWinTier::Win,
                    "big_win" | "bigwin" => crate::taxonomy::BigWinTier::BigWin,
                    "mega_win" | "megawin" => crate::taxonomy::BigWinTier::MegaWin,
                    "epic_win" | "epicwin" => crate::taxonomy::BigWinTier::EpicWin,
                    "ultra_win" | "ultrawin" => crate::taxonomy::BigWinTier::UltraWin,
                    _ => crate::taxonomy::BigWinTier::Win,
                };
                Some(Stage::BigWinTier {
                    tier,
                    amount: get_f64("amount"),
                })
            }
            "cascade_start" => Some(Stage::CascadeStart),
            "cascade_step" => Some(Stage::CascadeStep {
                step_index: data.get("step_index").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
                multiplier: get_f64("multiplier"),
            }),
            "cascade_end" => Some(Stage::CascadeEnd {
                total_steps: data
                    .get("total_steps")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as u32,
                total_win: get_f64("total_win"),
            }),
            "jackpot_trigger" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "mini" => crate::taxonomy::JackpotTier::Mini,
                    "minor" => crate::taxonomy::JackpotTier::Minor,
                    "major" => crate::taxonomy::JackpotTier::Major,
                    "grand" => crate::taxonomy::JackpotTier::Grand,
                    _ => crate::taxonomy::JackpotTier::Mini,
                };
                Some(Stage::JackpotTrigger { tier })
            }
            "jackpot_present" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "mini" => crate::taxonomy::JackpotTier::Mini,
                    "minor" => crate::taxonomy::JackpotTier::Minor,
                    "major" => crate::taxonomy::JackpotTier::Major,
                    "grand" => crate::taxonomy::JackpotTier::Grand,
                    _ => crate::taxonomy::JackpotTier::Mini,
                };
                Some(Stage::JackpotPresent {
                    amount: get_f64("amount"),
                    tier,
                })
            }
            "jackpot_end" => Some(Stage::JackpotEnd),
            // P1.5: New jackpot stages
            "jackpot_buildup" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "mini" => crate::taxonomy::JackpotTier::Mini,
                    "minor" => crate::taxonomy::JackpotTier::Minor,
                    "major" => crate::taxonomy::JackpotTier::Major,
                    "grand" => crate::taxonomy::JackpotTier::Grand,
                    _ => crate::taxonomy::JackpotTier::Mini,
                };
                Some(Stage::JackpotBuildup { tier })
            }
            "jackpot_reveal" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "mini" => crate::taxonomy::JackpotTier::Mini,
                    "minor" => crate::taxonomy::JackpotTier::Minor,
                    "major" => crate::taxonomy::JackpotTier::Major,
                    "grand" => crate::taxonomy::JackpotTier::Grand,
                    _ => crate::taxonomy::JackpotTier::Mini,
                };
                Some(Stage::JackpotReveal {
                    amount: get_f64("amount"),
                    tier,
                })
            }
            "jackpot_celebration" => {
                let tier_str = get_string("tier").unwrap_or_default();
                let tier = match tier_str.to_lowercase().as_str() {
                    "mini" => crate::taxonomy::JackpotTier::Mini,
                    "minor" => crate::taxonomy::JackpotTier::Minor,
                    "major" => crate::taxonomy::JackpotTier::Major,
                    "grand" => crate::taxonomy::JackpotTier::Grand,
                    _ => crate::taxonomy::JackpotTier::Mini,
                };
                Some(Stage::JackpotCelebration {
                    amount: get_f64("amount"),
                    tier,
                })
            }
            "idle_start" => Some(Stage::IdleStart),
            "idle_loop" => Some(Stage::IdleLoop),
            "menu_open" => Some(Stage::MenuOpen {
                menu_name: get_string("menu_name"),
            }),
            "menu_close" => Some(Stage::MenuClose),
            "custom" => Some(Stage::Custom {
                name: get_string("name").unwrap_or_else(|| name.to_string()),
                id: data.get("id").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
            }),
            // P0.13-P0.17: New stages
            "near_miss" => Some(Stage::NearMiss {
                reel_index: data
                    .get("reel_index")
                    .and_then(|v| v.as_u64())
                    .map(|v| v as u8),
                reason: get_string("reason"),
                proximity: get_f64("proximity"),
            }),
            "symbol_upgrade" => Some(Stage::SymbolUpgrade {
                reel_index: get_u8("reel_index"),
                row_index: get_u8("row_index"),
                from_symbol: data
                    .get("from_symbol")
                    .and_then(|v| v.as_u64())
                    .map(|v| v as u32),
                to_symbol: data.get("to_symbol").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
                upgrade_tier: get_u8("upgrade_tier"),
            }),
            "mystery_reveal" => Some(Stage::MysteryReveal {
                mystery_count: get_u8("mystery_count"),
                revealed_symbol: data
                    .get("revealed_symbol")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as u32,
                simultaneous: data
                    .get("simultaneous")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
            }),
            "multiplier_apply" => Some(Stage::MultiplierApply {
                multiplier: get_f64("multiplier"),
                base_amount: get_f64("base_amount"),
                final_amount: get_f64("final_amount"),
            }),
            _ => None,
        }
    }
}

/// Stage category for grouping
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StageCategory {
    SpinLifecycle,
    Anticipation,
    WinLifecycle,
    Feature,
    Cascade,
    Bonus,
    Gamble,
    Jackpot,
    UI,
    Special,
}

impl StageCategory {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::SpinLifecycle => "Spin Lifecycle",
            Self::Anticipation => "Anticipation",
            Self::WinLifecycle => "Win Lifecycle",
            Self::Feature => "Features",
            Self::Cascade => "Cascade/Tumble",
            Self::Bonus => "Bonus Games",
            Self::Gamble => "Gamble/Risk",
            Self::Jackpot => "Jackpot",
            Self::UI => "UI/Idle",
            Self::Special => "Special",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stage_serialization() {
        let stage = Stage::ReelStop {
            reel_index: 2,
            symbols: vec![1, 2, 3],
        };
        let json = serde_json::to_string(&stage).unwrap();
        assert!(json.contains("reel_stop"));
        assert!(json.contains("reel_index"));

        let deserialized: Stage = serde_json::from_str(&json).unwrap();
        assert_eq!(stage, deserialized);
    }

    #[test]
    fn test_stage_category() {
        assert_eq!(Stage::SpinStart.category(), StageCategory::SpinLifecycle);
        assert_eq!(
            Stage::AnticipationOn {
                reel_index: 0,
                reason: None
            }
            .category(),
            StageCategory::Anticipation
        );
        assert_eq!(
            Stage::BigWinTier {
                tier: BigWinTier::MegaWin,
                amount: 0.0
            }
            .category(),
            StageCategory::WinLifecycle
        );
    }

    #[test]
    fn test_is_looping() {
        assert!(Stage::ReelSpinning { reel_index: 0 }.is_looping());
        assert!(Stage::IdleLoop.is_looping());
        assert!(!Stage::SpinStart.is_looping());
        assert!(!Stage::ReelStop {
            reel_index: 0,
            symbols: vec![]
        }
        .is_looping());
    }
}
