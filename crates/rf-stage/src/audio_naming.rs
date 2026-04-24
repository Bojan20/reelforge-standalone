//! Audio Asset Naming — Standardized audio asset names for every Stage
//!
//! Maps Stage → canonical audio asset ID using FluxForge naming convention:
//!   - `sfx_*`  — one-shot sound effects
//!   - `mus_*`  — music loops and outros
//!   - `amb_*`  — ambient beds (loops)
//!   - `trn_*`  — transition stingers
//!   - `ui_*`   — UI interaction sounds
//!
//! ## 15 Audio Categories
//!
//! | Category       | Prefix | Examples                                      |
//! |----------------|--------|-----------------------------------------------|
//! | Spin Core      | sfx_   | spin_press, reel_spin_loop, reel_stop_N       |
//! | Anticipation   | sfx_   | anticipation_on_N, tension_layer_N_LN         |
//! | Win Present    | sfx_   | win_present, win_line_show                    |
//! | Rollup         | sfx_   | rollup_start, rollup_tick, rollup_end          |
//! | Free Spins     | sfx_   | free_spins_enter, free_spins_retrigger         |
//! | Hold & Win     | sfx_   | hold_and_win_enter, hold_and_win_step          |
//! | Pick Feature   | sfx_   | pick_feature_enter, pick_choice, pick_reveal   |
//! | Wheel Feature  | sfx_   | wheel_feature_enter, wheel_spin, wheel_stop    |
//! | Cascade        | sfx_   | cascade_start, cascade_step_N, cascade_end     |
//! | Gamble         | sfx_   | gamble_start, gamble_choice, gamble_win/lose    |
//! | Jackpot        | sfx_   | jackpot_trigger, jackpot_buildup, celebration  |
//! | UI             | ui_    | idle_start, menu_open, menu_close              |
//! | Music          | mus_   | base_game_loop, free_spins_loop, _loop_end     |
//! | Ambient        | amb_   | base_game_loop, free_spins_loop, feature_loop  |
//! | Transitions    | trn_   | base_to_free_spins, free_spins_to_base         |

use crate::stage::Stage;
use crate::taxonomy::{BigWinTier, FeatureType, GambleResult, JackpotTier};

/// Audio asset category
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AudioCategory {
    /// One-shot SFX (spin, reel, win, feature events)
    Sfx,
    /// Music loops and outros
    Music,
    /// Ambient beds (looping backgrounds)
    Ambient,
    /// Transition stingers between game states
    Transition,
    /// UI interaction sounds
    Ui,
}

impl AudioCategory {
    pub fn prefix(&self) -> &'static str {
        match self {
            Self::Sfx => "sfx",
            Self::Music => "mus",
            Self::Ambient => "amb",
            Self::Transition => "trn",
            Self::Ui => "ui",
        }
    }
}

/// An audio asset binding — links a Stage to one or more audio asset IDs
#[derive(Debug, Clone)]
pub struct AudioAssetBinding {
    /// Primary asset ID (e.g., "sfx_reel_stop_2")
    pub asset_id: String,
    /// Category for bus routing
    pub category: AudioCategory,
    /// Whether this asset should loop
    pub looping: bool,
    /// Whether this replaces or layers on top of current audio in same category
    pub exclusive: bool,
}

impl AudioAssetBinding {
    fn sfx(id: &str) -> Self {
        Self {
            asset_id: format!("sfx_{id}"),
            category: AudioCategory::Sfx,
            looping: false,
            exclusive: false,
        }
    }

    fn sfx_loop(id: &str) -> Self {
        Self {
            asset_id: format!("sfx_{id}"),
            category: AudioCategory::Sfx,
            looping: true,
            exclusive: false,
        }
    }

    fn music(id: &str, looping: bool) -> Self {
        Self {
            asset_id: format!("mus_{id}"),
            category: AudioCategory::Music,
            looping,
            exclusive: true, // music is always exclusive (one at a time)
        }
    }

    fn ambient(id: &str) -> Self {
        Self {
            asset_id: format!("amb_{id}"),
            category: AudioCategory::Ambient,
            looping: true,
            exclusive: true,
        }
    }

    fn transition(from: &str, to: &str) -> Self {
        Self {
            asset_id: format!("trn_{from}_to_{to}"),
            category: AudioCategory::Transition,
            looping: false,
            exclusive: false,
        }
    }

    fn ui(id: &str) -> Self {
        Self {
            asset_id: format!("ui_{id}"),
            category: AudioCategory::Ui,
            looping: false,
            exclusive: false,
        }
    }
}

/// Resolve a Stage into its canonical audio asset bindings.
///
/// Returns all audio assets that should trigger for this stage.
/// Most stages produce 1 binding, some produce multiple (e.g., FeatureEnter
/// produces both an SFX and a music/ambient change).
pub fn resolve_audio_assets(stage: &Stage) -> Vec<AudioAssetBinding> {
    match stage {
        // ═══════════════════════════════════════════════════════════════
        // SPIN CORE
        // ═══════════════════════════════════════════════════════════════
        Stage::UiSpinPress => vec![AudioAssetBinding::sfx("spin_press")],

        Stage::ReelSpinLoop => vec![AudioAssetBinding::sfx_loop("reel_spin_loop")],

        Stage::ReelSpinning { reel_index } => {
            vec![AudioAssetBinding::sfx(&format!("reel_spinning_{reel_index}"))]
        }

        Stage::ReelSpinningStart { reel_index } => {
            vec![AudioAssetBinding::sfx(&format!("reel_spinning_start_{reel_index}"))]
        }

        Stage::ReelSpinningStop { reel_index } => {
            vec![AudioAssetBinding::sfx(&format!("reel_spinning_stop_{reel_index}"))]
        }

        Stage::ReelStop { reel_index, .. } => {
            vec![AudioAssetBinding::sfx(&format!("reel_stop_{reel_index}"))]
        }

        Stage::EvaluateWins => vec![AudioAssetBinding::sfx("evaluate_wins")],

        Stage::SpinEnd => vec![AudioAssetBinding::sfx("spin_end")],

        // ═══════════════════════════════════════════════════════════════
        // ANTICIPATION
        // ═══════════════════════════════════════════════════════════════
        Stage::AnticipationOn { reel_index, .. } => {
            vec![AudioAssetBinding::sfx(&format!("anticipation_on_{reel_index}"))]
        }

        Stage::AnticipationOff { reel_index } => {
            vec![AudioAssetBinding::sfx(&format!("anticipation_off_{reel_index}"))]
        }

        Stage::AnticipationTensionLayer {
            reel_index,
            tension_level,
            ..
        } => vec![AudioAssetBinding::sfx(&format!(
            "anticipation_tension_{reel_index}_l{tension_level}"
        ))],

        // ═══════════════════════════════════════════════════════════════
        // WIN PRESENTATION
        // ═══════════════════════════════════════════════════════════════
        Stage::WinPresent { .. } => vec![AudioAssetBinding::sfx("win_present")],

        Stage::WinLineShow { line_index, .. } => {
            vec![AudioAssetBinding::sfx(&format!("win_line_show_{line_index}"))]
        }

        Stage::BigWinTier { tier, .. } => {
            let tier_name = match tier {
                BigWinTier::Win => "win",
                BigWinTier::BigWin => "big_win",
                BigWinTier::MegaWin => "mega_win",
                BigWinTier::EpicWin => "epic_win",
                BigWinTier::UltraWin => "ultra_win",
                BigWinTier::Custom(n) => {
                    return vec![
                        AudioAssetBinding::sfx(&format!("win_tier_{n}")),
                        AudioAssetBinding::music(&format!("win_tier_{n}_loop"), true),
                    ];
                }
            };
            vec![
                AudioAssetBinding::sfx(tier_name),
                AudioAssetBinding::music(&format!("{tier_name}_loop"), true),
            ]
        }

        // ═══════════════════════════════════════════════════════════════
        // ROLLUP
        // ═══════════════════════════════════════════════════════════════
        Stage::RollupStart { .. } => vec![AudioAssetBinding::sfx_loop("rollup_loop")],

        Stage::RollupTick { .. } => vec![AudioAssetBinding::sfx("rollup_tick")],

        Stage::RollupEnd { .. } => vec![AudioAssetBinding::sfx("rollup_end")],

        // ═══════════════════════════════════════════════════════════════
        // FEATURES (Free Spins, Hold & Win, Pick, Wheel — via FeatureType)
        // ═══════════════════════════════════════════════════════════════
        Stage::FeatureEnter { feature_type, .. } => {
            let name = feature_type_name(feature_type);
            let mut bindings = vec![
                AudioAssetBinding::sfx(&format!("{name}_enter")),
                AudioAssetBinding::transition("base", name),
            ];
            // Music + ambient change on feature enter
            bindings.push(AudioAssetBinding::music(&format!("{name}_loop"), true));
            bindings.push(AudioAssetBinding::ambient(&format!("{name}_loop")));
            bindings
        }

        Stage::FeatureStep { .. } => vec![AudioAssetBinding::sfx("feature_step")],

        Stage::FeatureRetrigger { .. } => vec![AudioAssetBinding::sfx("feature_retrigger")],

        Stage::FeatureExit { .. } => {
            vec![
                AudioAssetBinding::sfx("feature_exit"),
                // Return to base game music + ambient
                AudioAssetBinding::music("base_game_loop", true),
                AudioAssetBinding::ambient("base_game_loop"),
            ]
        }

        // ═══════════════════════════════════════════════════════════════
        // CASCADE
        // ═══════════════════════════════════════════════════════════════
        Stage::CascadeStart => vec![AudioAssetBinding::sfx("cascade_start")],

        Stage::CascadeStep { step_index, .. } => {
            vec![AudioAssetBinding::sfx(&format!("cascade_step_{step_index}"))]
        }

        Stage::CascadeEnd { .. } => vec![AudioAssetBinding::sfx("cascade_end")],

        // ═══════════════════════════════════════════════════════════════
        // BONUS / PICK
        // ═══════════════════════════════════════════════════════════════
        Stage::BonusEnter { .. } => vec![
            AudioAssetBinding::sfx("pick_feature_enter"),
            AudioAssetBinding::transition("base", "pick_feature"),
            AudioAssetBinding::music("pick_feature_loop", true),
        ],

        Stage::BonusChoice { .. } => vec![AudioAssetBinding::sfx("pick_choice")],

        Stage::BonusReveal { is_terminal, .. } => {
            if *is_terminal {
                vec![AudioAssetBinding::sfx("pick_reveal_final")]
            } else {
                vec![AudioAssetBinding::sfx("pick_reveal")]
            }
        }

        Stage::BonusExit { .. } => vec![
            AudioAssetBinding::sfx("pick_feature_exit"),
            AudioAssetBinding::transition("pick_feature", "base"),
            AudioAssetBinding::music("base_game_loop", true),
            AudioAssetBinding::ambient("base_game_loop"),
        ],

        Stage::BonusStart { .. } => vec![AudioAssetBinding::sfx("bonus_start")],
        Stage::BonusPrizeReveal { .. } => vec![AudioAssetBinding::sfx("bonus_prize_reveal")],
        Stage::BonusComplete { .. } => vec![AudioAssetBinding::sfx("bonus_complete")],

        // ═══════════════════════════════════════════════════════════════
        // GAMBLE
        // ═══════════════════════════════════════════════════════════════
        Stage::GambleStart { .. } => vec![
            AudioAssetBinding::sfx("gamble_start"),
            AudioAssetBinding::transition("base", "gamble"),
        ],

        Stage::GambleChoice { .. } => vec![AudioAssetBinding::sfx("gamble_choice")],

        Stage::GambleResultStage { result, .. } => {
            let name = match result {
                GambleResult::Win => "gamble_win",
                GambleResult::Lose => "gamble_lose",
                GambleResult::Draw => "gamble_draw",
                GambleResult::Collected => "gamble_collect",
            };
            vec![AudioAssetBinding::sfx(name)]
        }

        Stage::GambleEnd { .. } => vec![
            AudioAssetBinding::sfx("gamble_end"),
            AudioAssetBinding::transition("gamble", "base"),
            AudioAssetBinding::music("base_game_loop", true),
        ],

        // ═══════════════════════════════════════════════════════════════
        // JACKPOT
        // ═══════════════════════════════════════════════════════════════
        Stage::JackpotTrigger { tier } => {
            let t = jackpot_tier_name(tier);
            vec![AudioAssetBinding::sfx(&format!("jackpot_trigger_{t}"))]
        }

        Stage::JackpotPresent { tier, .. } => {
            let t = jackpot_tier_name(tier);
            vec![
                AudioAssetBinding::sfx(&format!("jackpot_present_{t}")),
                AudioAssetBinding::music("jackpot_loop", true),
            ]
        }

        Stage::JackpotBuildup { tier } => {
            let t = jackpot_tier_name(tier);
            vec![AudioAssetBinding::sfx(&format!("jackpot_buildup_{t}"))]
        }

        Stage::JackpotReveal { tier, .. } => {
            let t = jackpot_tier_name(tier);
            vec![AudioAssetBinding::sfx(&format!("jackpot_reveal_{t}"))]
        }

        Stage::JackpotCelebration { tier, .. } => {
            let t = jackpot_tier_name(tier);
            vec![AudioAssetBinding::sfx(&format!("jackpot_celebration_{t}"))]
        }

        Stage::JackpotEnd => vec![
            AudioAssetBinding::sfx("jackpot_end"),
            AudioAssetBinding::music("jackpot_loop_end", false),
            // Return to base
            AudioAssetBinding::music("base_game_loop", true),
        ],

        // ═══════════════════════════════════════════════════════════════
        // UI
        // ═══════════════════════════════════════════════════════════════
        Stage::IdleStart => vec![AudioAssetBinding::ui("idle_start")],
        Stage::IdleLoop => vec![AudioAssetBinding::ui("idle_loop")],
        Stage::MenuOpen { .. } => vec![AudioAssetBinding::ui("menu_open")],
        Stage::MenuClose => vec![AudioAssetBinding::ui("menu_close")],
        Stage::AutoplayStart { .. } => vec![AudioAssetBinding::ui("autoplay_start")],
        Stage::AutoplayStop { .. } => vec![AudioAssetBinding::ui("autoplay_stop")],

        // ═══════════════════════════════════════════════════════════════
        // SPECIAL
        // ═══════════════════════════════════════════════════════════════
        Stage::SymbolTransform { .. } => vec![AudioAssetBinding::sfx("symbol_transform")],
        Stage::WildExpand { .. } => vec![AudioAssetBinding::sfx("wild_expand")],
        Stage::MultiplierChange { .. } => vec![AudioAssetBinding::sfx("multiplier_change")],
        Stage::NearMiss { .. } => vec![AudioAssetBinding::sfx("near_miss")],
        Stage::SymbolUpgrade { .. } => vec![AudioAssetBinding::sfx("symbol_upgrade")],
        Stage::MysteryReveal { .. } => vec![AudioAssetBinding::sfx("mystery_reveal")],
        Stage::MultiplierApply { .. } => vec![AudioAssetBinding::sfx("multiplier_apply")],
        Stage::Custom { name, .. } => {
            vec![AudioAssetBinding::sfx(&format!("custom_{}", name.to_lowercase()))]
        }

        // ═══════════════════════════════════════════════════════════════
        // FEATURE TRANSITIONS & SUMMARY
        // ═══════════════════════════════════════════════════════════════
        Stage::FsSummary { .. } => vec![
            // FS summary sting — plays over exit transition plaque
            AudioAssetBinding::sfx("fs_summary_sting"),
            // Soft rollup accent for total win display
            AudioAssetBinding::sfx("fs_summary_rollup"),
        ],

        Stage::UiSkipPress { was_big_win, .. } => {
            if *was_big_win {
                vec![AudioAssetBinding::ui("ui_skip_big_win")]
            } else {
                vec![AudioAssetBinding::ui("ui_skip_press")]
            }
        }
    }
}

/// Get all canonical audio asset IDs for base game state.
/// These are the default assets playing when no feature is active.
pub fn base_game_assets() -> Vec<AudioAssetBinding> {
    vec![
        AudioAssetBinding::music("base_game_loop", true),
        AudioAssetBinding::ambient("base_game_loop"),
    ]
}

/// Get transition pair asset IDs for a feature type.
/// Returns (enter_transition, exit_transition) asset IDs.
pub fn feature_transitions(feature_type: &FeatureType) -> (String, String) {
    let name = feature_type_name(feature_type);
    (
        format!("trn_base_to_{name}"),
        format!("trn_{name}_to_base"),
    )
}

/// List ALL canonical asset IDs that a game should provide.
/// Useful for completeness checking and asset pipeline validation.
pub fn all_canonical_asset_ids() -> Vec<&'static str> {
    vec![
        // Spin Core
        "sfx_spin_press",
        "sfx_reel_spin_loop",
        "sfx_reel_stop_0",
        "sfx_reel_stop_1",
        "sfx_reel_stop_2",
        "sfx_reel_stop_3",
        "sfx_reel_stop_4",
        "sfx_evaluate_wins",
        "sfx_spin_end",
        // Anticipation
        "sfx_anticipation_on_0",
        "sfx_anticipation_on_1",
        "sfx_anticipation_on_2",
        "sfx_anticipation_on_3",
        "sfx_anticipation_on_4",
        "sfx_anticipation_off_0",
        "sfx_anticipation_tension_0_l1",
        "sfx_anticipation_tension_0_l2",
        "sfx_anticipation_tension_0_l3",
        "sfx_anticipation_tension_0_l4",
        // Win Presentation
        "sfx_win_present",
        "sfx_win_line_show_0",
        "sfx_big_win",
        "sfx_mega_win",
        "sfx_epic_win",
        "sfx_ultra_win",
        // Rollup
        "sfx_rollup_loop",
        "sfx_rollup_tick",
        "sfx_rollup_end",
        // Cascade
        "sfx_cascade_start",
        "sfx_cascade_step_0",
        "sfx_cascade_step_1",
        "sfx_cascade_step_2",
        "sfx_cascade_end",
        // Gamble
        "sfx_gamble_start",
        "sfx_gamble_choice",
        "sfx_gamble_win",
        "sfx_gamble_lose",
        "sfx_gamble_draw",
        "sfx_gamble_end",
        // Jackpot
        "sfx_jackpot_trigger_mini",
        "sfx_jackpot_trigger_minor",
        "sfx_jackpot_trigger_major",
        "sfx_jackpot_trigger_grand",
        "sfx_jackpot_present_grand",
        "sfx_jackpot_buildup_grand",
        "sfx_jackpot_reveal_grand",
        "sfx_jackpot_celebration_grand",
        "sfx_jackpot_end",
        // Feature SFX
        "sfx_free_spins_enter",
        "sfx_hold_and_win_enter",
        "sfx_pick_feature_enter",
        "sfx_wheel_feature_enter",
        "sfx_feature_step",
        "sfx_feature_retrigger",
        "sfx_feature_exit",
        "sfx_pick_choice",
        "sfx_pick_reveal",
        "sfx_pick_reveal_final",
        "sfx_bonus_start",
        "sfx_bonus_prize_reveal",
        "sfx_bonus_complete",
        // Special
        "sfx_symbol_transform",
        "sfx_wild_expand",
        "sfx_multiplier_change",
        "sfx_near_miss",
        "sfx_symbol_upgrade",
        "sfx_mystery_reveal",
        "sfx_multiplier_apply",
        // UI
        "ui_idle_start",
        "ui_idle_loop",
        "ui_menu_open",
        "ui_menu_close",
        "ui_autoplay_start",
        "ui_autoplay_stop",
        // Music
        "mus_base_game_loop",
        "mus_free_spins_loop",
        "mus_free_spins_loop_end",
        "mus_hold_and_win_loop",
        "mus_hold_and_win_loop_end",
        "mus_pick_feature_loop",
        "mus_pick_feature_loop_end",
        "mus_wheel_feature_loop",
        "mus_wheel_feature_loop_end",
        "mus_big_win_loop",
        "mus_big_win_loop_end",
        "mus_jackpot_loop",
        "mus_jackpot_loop_end",
        // Ambient
        "amb_base_game_loop",
        "amb_free_spins_loop",
        "amb_feature_loop",
        // Transitions
        "trn_base_to_free_spins",
        "trn_free_spins_to_base",
        "trn_base_to_hold_and_win",
        "trn_hold_and_win_to_base",
        "trn_base_to_pick_feature",
        "trn_base_to_wheel_feature",
        "trn_wheel_feature_to_base",
        "trn_base_to_gamble",
        "trn_gamble_to_base",
        "trn_base_to_jackpot",
        "trn_jackpot_to_base",
    ]
}

/// Check which canonical assets are missing from a provided asset list.
pub fn missing_assets(provided: &[&str]) -> Vec<&'static str> {
    let provided_set: std::collections::HashSet<&str> = provided.iter().copied().collect();
    all_canonical_asset_ids()
        .into_iter()
        .filter(|id| !provided_set.contains(id))
        .collect()
}

/// Asset coverage percentage
pub fn coverage_percent(provided: &[&str]) -> f32 {
    let total = all_canonical_asset_ids().len() as f32;
    let provided_set: std::collections::HashSet<&str> = provided.iter().copied().collect();
    let covered = all_canonical_asset_ids()
        .iter()
        .filter(|id| provided_set.contains(**id))
        .count() as f32;
    (covered / total) * 100.0
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

fn feature_type_name(ft: &FeatureType) -> &'static str {
    match ft {
        FeatureType::FreeSpins => "free_spins",
        FeatureType::BonusGame => "bonus_game",
        FeatureType::PickBonus => "pick_feature",
        FeatureType::WheelBonus => "wheel_feature",
        FeatureType::Respin => "respin",
        FeatureType::HoldAndSpin => "hold_and_win",
        FeatureType::ExpandingWilds => "expanding_wilds",
        FeatureType::StickyWilds => "sticky_wilds",
        FeatureType::Multiplier => "multiplier_feature",
        FeatureType::Cascade => "cascade",
        FeatureType::MysterySymbols => "mystery_symbols",
        FeatureType::WalkingWilds => "walking_wilds",
        FeatureType::ColossalReels => "colossal_reels",
        FeatureType::Megaways => "megaways",
        FeatureType::Custom(_) => "custom_feature",
    }
}

fn jackpot_tier_name(tier: &JackpotTier) -> &'static str {
    match tier {
        JackpotTier::Mini => "mini",
        JackpotTier::Minor => "minor",
        JackpotTier::Major => "major",
        JackpotTier::Grand => "grand",
        JackpotTier::Custom(_) => "custom",
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spin_press_asset() {
        let bindings = resolve_audio_assets(&Stage::UiSpinPress);
        assert_eq!(bindings.len(), 1);
        assert_eq!(bindings[0].asset_id, "sfx_spin_press");
        assert!(!bindings[0].looping);
    }

    #[test]
    fn test_reel_stop_per_reel() {
        for i in 0..5 {
            let bindings = resolve_audio_assets(&Stage::ReelStop {
                reel_index: i,
                symbols: vec![],
            });
            assert_eq!(bindings[0].asset_id, format!("sfx_reel_stop_{i}"));
        }
    }

    #[test]
    fn test_big_win_produces_sfx_and_music() {
        let bindings = resolve_audio_assets(&Stage::BigWinTier {
            tier: BigWinTier::MegaWin,
            amount: 1000.0,
        });
        assert_eq!(bindings.len(), 2);
        assert_eq!(bindings[0].asset_id, "sfx_mega_win");
        assert_eq!(bindings[1].asset_id, "mus_mega_win_loop");
        assert!(bindings[1].looping);
    }

    #[test]
    fn test_feature_enter_produces_sfx_transition_music_ambient() {
        let bindings = resolve_audio_assets(&Stage::FeatureEnter {
            feature_type: FeatureType::FreeSpins,
            total_steps: Some(10),
            multiplier: 1.0,
        });
        assert_eq!(bindings.len(), 4);
        assert_eq!(bindings[0].asset_id, "sfx_free_spins_enter");
        assert_eq!(bindings[1].asset_id, "trn_base_to_free_spins");
        assert_eq!(bindings[2].asset_id, "mus_free_spins_loop");
        assert_eq!(bindings[3].asset_id, "amb_free_spins_loop");
    }

    #[test]
    fn test_feature_exit_returns_to_base() {
        let bindings = resolve_audio_assets(&Stage::FeatureExit { total_win: 500.0 });
        assert!(bindings.iter().any(|b| b.asset_id == "mus_base_game_loop"));
        assert!(bindings.iter().any(|b| b.asset_id == "amb_base_game_loop"));
    }

    #[test]
    fn test_jackpot_tiers() {
        let bindings = resolve_audio_assets(&Stage::JackpotTrigger {
            tier: JackpotTier::Grand,
        });
        assert_eq!(bindings[0].asset_id, "sfx_jackpot_trigger_grand");
    }

    #[test]
    fn test_gamble_result_win_lose() {
        let win = resolve_audio_assets(&Stage::GambleResultStage {
            result: GambleResult::Win,
            new_amount: 200.0,
        });
        assert_eq!(win[0].asset_id, "sfx_gamble_win");

        let lose = resolve_audio_assets(&Stage::GambleResultStage {
            result: GambleResult::Lose,
            new_amount: 0.0,
        });
        assert_eq!(lose[0].asset_id, "sfx_gamble_lose");
    }

    #[test]
    fn test_canonical_list_not_empty() {
        let all = all_canonical_asset_ids();
        assert!(all.len() > 90);
    }

    #[test]
    fn test_coverage_full() {
        let all = all_canonical_asset_ids();
        let coverage = coverage_percent(&all);
        assert!((coverage - 100.0).abs() < f32::EPSILON);
    }

    #[test]
    fn test_missing_assets() {
        let provided = &["sfx_spin_press", "sfx_reel_stop_0"];
        let missing = missing_assets(provided);
        assert!(missing.len() > 80);
        assert!(!missing.contains(&"sfx_spin_press"));
    }

    #[test]
    fn test_transition_pairs() {
        let (enter, exit) = feature_transitions(&FeatureType::FreeSpins);
        assert_eq!(enter, "trn_base_to_free_spins");
        assert_eq!(exit, "trn_free_spins_to_base");
    }

    #[test]
    fn test_all_stages_produce_at_least_one_binding() {
        // Every stage variant should produce at least one audio binding
        let stages = vec![
            Stage::UiSpinPress,
            Stage::ReelSpinLoop,
            Stage::ReelStop { reel_index: 0, symbols: vec![] },
            Stage::EvaluateWins,
            Stage::SpinEnd,
            Stage::AnticipationOn { reel_index: 0, reason: None },
            Stage::WinPresent { win_amount: 100.0, line_count: 3 },
            Stage::RollupStart { target_amount: 100.0, start_amount: 0.0 },
            Stage::RollupTick { current_amount: 50.0, progress: 0.5 },
            Stage::RollupEnd { final_amount: 100.0 },
            Stage::CascadeStart,
            Stage::CascadeStep { step_index: 0, multiplier: 1.0 },
            Stage::CascadeEnd { total_steps: 3, total_win: 100.0 },
            Stage::GambleStart { stake_amount: 50.0 },
            Stage::GambleEnd { collected_amount: 100.0 },
            Stage::JackpotTrigger { tier: JackpotTier::Grand },
            Stage::JackpotEnd,
            Stage::IdleStart,
            Stage::MenuOpen { menu_name: Some("settings".into()) },
            Stage::Custom { name: "test".into(), id: 0 },
        ];
        for stage in &stages {
            let bindings = resolve_audio_assets(stage);
            assert!(!bindings.is_empty(), "Stage {:?} produced no bindings", stage);
        }
    }
}
