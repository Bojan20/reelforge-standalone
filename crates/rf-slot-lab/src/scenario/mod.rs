//! Scenario System — Demo sequences and scripted outcomes
//!
//! This module provides a scenario system for creating and playing
//! scripted sequences of slot outcomes for demos and audio testing.
//!
//! ## Key Components
//!
//! - `DemoScenario` — A sequence of scripted spins
//! - `ScriptedOutcome` — A single scripted outcome
//! - `ScenarioPlayback` — Playback engine for scenarios
//! - `ScenarioPresets` — Built-in demo scenarios
//!
//! ## Built-in Presets
//!
//! - `win_showcase` — All win tiers from lose to ultra
//! - `free_spins_demo` — Free spins trigger and sequence
//! - `cascade_demo` — Cascade chain demonstration
//! - `jackpot_demo` — Jackpot wheel sequence
//! - `stress_test` — Rapid fire for testing

mod presets;

// Placeholder types for now
use serde::{Deserialize, Serialize};

use crate::model::GameModel;

/// Errors produced when validating a scenario against a game model.
///
/// BUG#63 — A scripted scenario must be self-consistent against the active
/// `GameModel` before being handed to playback. Pre-fix the FFI layer only
/// rejected `SpecificGrid` outcomes whose REEL/ROW count diverged. Anything
/// else — invalid symbol IDs, NaN win ratios, billion-spin free spin
/// triggers — slipped through and corrupted downstream win evaluation,
/// session economy, and (in the symbol-id case) caused out-of-bounds reads
/// in payline matchers that index into the symbol table by id.
#[derive(Debug, Clone, thiserror::Error)]
pub enum ScenarioValidationError {
    /// A `SpecificGrid` outcome has the wrong number of reels.
    #[error(
        "spin #{spin_index} SpecificGrid has {got} reels but game model expects {expected}"
    )]
    WrongReelCount {
        spin_index: usize,
        expected: usize,
        got: usize,
    },

    /// A `SpecificGrid` outcome has a reel with the wrong number of rows.
    #[error(
        "spin #{spin_index} SpecificGrid reel {reel_index} has {got} rows but game model expects {expected}"
    )]
    WrongRowCount {
        spin_index: usize,
        reel_index: usize,
        expected: usize,
        got: usize,
    },

    /// A `SpecificGrid` cell references a symbol id that doesn't exist in the
    /// active model's symbol set. Without this check, downstream payline
    /// matching would either silently mis-evaluate the win or, for some
    /// matchers that index a fixed-size table, read past its end.
    #[error(
        "spin #{spin_index} SpecificGrid cell ({reel_index},{row_index}) references unknown symbol id {symbol_id}"
    )]
    UnknownSymbolId {
        spin_index: usize,
        reel_index: usize,
        row_index: usize,
        symbol_id: u32,
    },

    /// A scripted win ratio is non-finite (NaN/±Inf) or negative.
    #[error(
        "spin #{spin_index} {variant} has invalid ratio {ratio}: must be finite and ≥ 0"
    )]
    InvalidWinRatio {
        spin_index: usize,
        variant: &'static str,
        ratio: f64,
    },

    /// A scripted free-spin count is unreasonably large (would never end the
    /// session) or zero (semantic bug — `TriggerFreeSpins { count: 0 }` is a
    /// no-op masquerading as a trigger).
    #[error(
        "spin #{spin_index} TriggerFreeSpins.count={count} out of allowed range [1, {max}]"
    )]
    InvalidFreeSpinCount {
        spin_index: usize,
        count: u32,
        max: u32,
    },

    /// A multiplier value is non-finite or negative.
    #[error(
        "spin #{spin_index} {variant} has invalid multiplier {value}: must be finite and ≥ 0"
    )]
    InvalidMultiplier {
        spin_index: usize,
        variant: &'static str,
        value: f64,
    },

    /// A cascade chain win count is unreasonably large.
    #[error(
        "spin #{spin_index} CascadeChain.wins={wins} out of allowed range [1, {max}]"
    )]
    InvalidCascadeWinCount {
        spin_index: usize,
        wins: u32,
        max: u32,
    },

    /// The scenario has zero spins. Combined with `LoopMode::Forever` /
    /// `LoopMode::Count(_)` / `LoopMode::PingPong` this would spin without
    /// producing any outcome — playback would silently advance forever.
    #[error("scenario has empty sequence; at least one spin is required")]
    EmptySequence,
}

/// Maximum free-spin trigger count — a single scenario step asking for more
/// than this would never complete in a normal session, almost certainly a
/// data error rather than a real intent.
pub const SCENARIO_MAX_FREE_SPINS: u32 = 10_000;

/// Maximum cascade chain length — same reasoning as above. Real cascade
/// games top out around 20–30 sequential cascades for showcase purposes;
/// 1000 is generous slack against unexpected configs.
pub const SCENARIO_MAX_CASCADE_WINS: u32 = 1_000;

/// Demo scenario — a sequence of scripted outcomes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DemoScenario {
    /// Scenario ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Description
    pub description: String,
    /// Sequence of scripted spins
    pub sequence: Vec<ScriptedSpin>,
    /// Loop mode
    pub loop_mode: LoopMode,
}

/// A single scripted spin
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptedSpin {
    /// Outcome to force
    pub outcome: ScriptedOutcome,
    /// Delay before this spin (ms)
    #[serde(default)]
    pub delay_before_ms: Option<f64>,
    /// Note/annotation
    #[serde(default)]
    pub note: Option<String>,
}

/// Scripted outcome types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScriptedOutcome {
    /// No win
    Lose,
    /// Small win
    SmallWin { ratio: f64 },
    /// Medium win
    MediumWin { ratio: f64 },
    /// Big win
    BigWin { ratio: f64 },
    /// Mega win
    MegaWin { ratio: f64 },
    /// Epic win
    EpicWin { ratio: f64 },
    /// Ultra win
    UltraWin { ratio: f64 },
    /// Trigger free spins
    TriggerFreeSpins { count: u32, multiplier: f64 },
    /// Trigger hold and win
    TriggerHoldAndWin,
    /// Trigger jackpot
    TriggerJackpot { tier: String },
    /// Near miss
    NearMiss { feature: String },
    /// Cascade chain
    CascadeChain { wins: u32 },
    /// Specific grid
    SpecificGrid { grid: Vec<Vec<u32>> },
}

/// Loop mode for scenarios
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum LoopMode {
    /// Play once
    #[default]
    Once,
    /// Loop forever
    Forever,
    /// Loop N times
    Count(u32),
    /// Ping-pong (forward then backward)
    PingPong,
}

impl DemoScenario {
    /// Create a new empty scenario
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            description: String::new(),
            sequence: Vec::new(),
            loop_mode: LoopMode::Once,
        }
    }

    /// Add a spin to the sequence
    pub fn add_spin(&mut self, outcome: ScriptedOutcome) {
        self.sequence.push(ScriptedSpin {
            outcome,
            delay_before_ms: None,
            note: None,
        });
    }

    /// Get sequence length
    pub fn len(&self) -> usize {
        self.sequence.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.sequence.is_empty()
    }

    /// Validate this scenario against a game model.
    ///
    /// Returns the first validation error found, or `Ok(())` if all spins are
    /// compatible. Call this after constructing a scenario from user input
    /// or deserialised data, BEFORE handing it to `ScenarioPlayback`.
    ///
    /// # BUG#63 — coverage
    ///
    /// Pre-fix this only verified `SpecificGrid` reel/row counts. Now it
    /// checks every variant of [`ScriptedOutcome`]:
    ///
    /// * `SpecificGrid` — reel count, row-per-reel count, and EVERY symbol
    ///   id is resolvable through the active symbol set (catches the
    ///   classic "scenario authored against a different game" failure).
    /// * `SmallWin/MediumWin/BigWin/MegaWin/EpicWin/UltraWin` — `ratio`
    ///   must be finite and non-negative. NaN/±Inf would otherwise leak
    ///   into the win-tier comparator and propagate to the session bank.
    /// * `TriggerFreeSpins` — `count` is in `[1, SCENARIO_MAX_FREE_SPINS]`
    ///   (zero is a no-op masquerading as a trigger; huge values would
    ///   never let the session conclude). `multiplier` must be finite ≥ 0.
    /// * `TriggerJackpot` — no extra check; the tier string is validated
    ///   downstream by the jackpot manager.
    /// * `CascadeChain` — `wins` is in `[1, SCENARIO_MAX_CASCADE_WINS]`.
    /// * Sequence — must contain at least one spin (looping forever over
    ///   an empty sequence would silently advance with no outcomes).
    pub fn validate_against(&self, model: &GameModel) -> Result<(), ScenarioValidationError> {
        if self.sequence.is_empty() {
            return Err(ScenarioValidationError::EmptySequence);
        }

        let expected_reels = model.grid.reels as usize;
        let expected_rows = model.grid.rows as usize;
        // Snapshot the symbol set once — the conversion is non-trivial for
        // Custom sets and would otherwise rerun for every cell in every spin.
        let symbol_set = model.symbols.to_symbol_set();

        for (spin_index, spin) in self.sequence.iter().enumerate() {
            match &spin.outcome {
                ScriptedOutcome::Lose | ScriptedOutcome::TriggerHoldAndWin
                | ScriptedOutcome::NearMiss { .. }
                | ScriptedOutcome::TriggerJackpot { .. } => {
                    // No numeric payload to validate.
                }

                ScriptedOutcome::SmallWin { ratio } => {
                    check_ratio(spin_index, "SmallWin", *ratio)?;
                }
                ScriptedOutcome::MediumWin { ratio } => {
                    check_ratio(spin_index, "MediumWin", *ratio)?;
                }
                ScriptedOutcome::BigWin { ratio } => {
                    check_ratio(spin_index, "BigWin", *ratio)?;
                }
                ScriptedOutcome::MegaWin { ratio } => {
                    check_ratio(spin_index, "MegaWin", *ratio)?;
                }
                ScriptedOutcome::EpicWin { ratio } => {
                    check_ratio(spin_index, "EpicWin", *ratio)?;
                }
                ScriptedOutcome::UltraWin { ratio } => {
                    check_ratio(spin_index, "UltraWin", *ratio)?;
                }

                ScriptedOutcome::TriggerFreeSpins { count, multiplier } => {
                    if *count == 0 || *count > SCENARIO_MAX_FREE_SPINS {
                        return Err(ScenarioValidationError::InvalidFreeSpinCount {
                            spin_index,
                            count: *count,
                            max: SCENARIO_MAX_FREE_SPINS,
                        });
                    }
                    if !multiplier.is_finite() || *multiplier < 0.0 {
                        return Err(ScenarioValidationError::InvalidMultiplier {
                            spin_index,
                            variant: "TriggerFreeSpins",
                            value: *multiplier,
                        });
                    }
                }

                ScriptedOutcome::CascadeChain { wins } => {
                    if *wins == 0 || *wins > SCENARIO_MAX_CASCADE_WINS {
                        return Err(ScenarioValidationError::InvalidCascadeWinCount {
                            spin_index,
                            wins: *wins,
                            max: SCENARIO_MAX_CASCADE_WINS,
                        });
                    }
                }

                ScriptedOutcome::SpecificGrid { grid } => {
                    if grid.len() != expected_reels {
                        return Err(ScenarioValidationError::WrongReelCount {
                            spin_index,
                            expected: expected_reels,
                            got: grid.len(),
                        });
                    }
                    for (reel_index, reel) in grid.iter().enumerate() {
                        if reel.len() != expected_rows {
                            return Err(ScenarioValidationError::WrongRowCount {
                                spin_index,
                                reel_index,
                                expected: expected_rows,
                                got: reel.len(),
                            });
                        }
                        for (row_index, &symbol_id) in reel.iter().enumerate() {
                            if symbol_set.get(symbol_id).is_none() {
                                return Err(ScenarioValidationError::UnknownSymbolId {
                                    spin_index,
                                    reel_index,
                                    row_index,
                                    symbol_id,
                                });
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }
}

/// Helper: validate that a scripted win ratio is a finite, non-negative number.
#[inline]
fn check_ratio(
    spin_index: usize,
    variant: &'static str,
    ratio: f64,
) -> Result<(), ScenarioValidationError> {
    if !ratio.is_finite() || ratio < 0.0 {
        return Err(ScenarioValidationError::InvalidWinRatio {
            spin_index,
            variant,
            ratio,
        });
    }
    Ok(())
}

/// Scenario playback state
#[derive(Debug, Clone)]
pub struct ScenarioPlayback {
    scenario: DemoScenario,
    current_index: usize,
    loop_count: u32,
    direction: i32, // 1 = forward, -1 = backward (for ping-pong)
}

impl ScenarioPlayback {
    /// Create new playback
    pub fn new(scenario: DemoScenario) -> Self {
        Self {
            scenario,
            current_index: 0,
            loop_count: 0,
            direction: 1,
        }
    }

    /// Get next spin
    #[allow(clippy::should_implement_trait)]
    pub fn next(&mut self) -> Option<&ScriptedSpin> {
        if self.is_complete() {
            return None;
        }

        let spin = self.scenario.sequence.get(self.current_index)?;

        // Advance
        self.current_index = (self.current_index as i32 + self.direction) as usize;

        // Handle loop modes
        if self.current_index >= self.scenario.sequence.len() {
            match self.scenario.loop_mode {
                LoopMode::Once => {}
                LoopMode::Forever => {
                    self.current_index = 0;
                }
                LoopMode::Count(n) => {
                    self.loop_count += 1;
                    if self.loop_count < n {
                        self.current_index = 0;
                    }
                }
                LoopMode::PingPong => {
                    self.direction = -1;
                    self.current_index = self.scenario.sequence.len().saturating_sub(2);
                }
            }
        } else if self.direction == -1 && self.current_index == 0 {
            // Ping-pong reached start
            self.direction = 1;
            self.loop_count += 1;
        }

        Some(spin)
    }

    /// Check if playback is complete
    pub fn is_complete(&self) -> bool {
        match self.scenario.loop_mode {
            LoopMode::Once => self.current_index >= self.scenario.sequence.len(),
            LoopMode::Forever => false,
            LoopMode::Count(n) => self.loop_count >= n,
            LoopMode::PingPong => false, // Never complete
        }
    }

    /// Get progress (current, total)
    pub fn progress(&self) -> (usize, usize) {
        (self.current_index, self.scenario.sequence.len())
    }

    /// Reset playback
    pub fn reset(&mut self) {
        self.current_index = 0;
        self.loop_count = 0;
        self.direction = 1;
    }

    /// Get scenario reference
    pub fn scenario(&self) -> &DemoScenario {
        &self.scenario
    }

    /// Get current spin without advancing
    pub fn current(&self) -> Option<&ScriptedSpin> {
        self.scenario.sequence.get(self.current_index)
    }

    /// Skip to specific index
    pub fn skip_to(&mut self, index: usize) {
        if index < self.scenario.sequence.len() {
            self.current_index = index;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCENARIO REGISTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// Registry of available scenarios
#[derive(Debug, Default)]
pub struct ScenarioRegistry {
    scenarios: std::collections::HashMap<String, DemoScenario>,
}

impl ScenarioRegistry {
    /// Create new registry with built-in presets
    pub fn new() -> Self {
        let mut registry = Self::default();
        registry.register_presets();
        registry
    }

    /// Create empty registry (no presets)
    pub fn empty() -> Self {
        Self::default()
    }

    /// Register built-in presets
    pub fn register_presets(&mut self) {
        for scenario in presets::all_presets() {
            self.register(scenario);
        }
    }

    /// Register a scenario
    pub fn register(&mut self, scenario: DemoScenario) {
        self.scenarios.insert(scenario.id.clone(), scenario);
    }

    /// Get scenario by ID
    pub fn get(&self, id: &str) -> Option<&DemoScenario> {
        self.scenarios.get(id)
    }

    /// List all scenario IDs
    pub fn list(&self) -> Vec<&str> {
        self.scenarios.keys().map(|s| s.as_str()).collect()
    }

    /// List all scenarios with info
    pub fn list_with_info(&self) -> Vec<ScenarioInfo> {
        self.scenarios
            .values()
            .map(|s| ScenarioInfo {
                id: s.id.clone(),
                name: s.name.clone(),
                description: s.description.clone(),
                spin_count: s.sequence.len(),
                loop_mode: s.loop_mode,
            })
            .collect()
    }

    /// Create playback for a scenario
    pub fn create_playback(&self, id: &str) -> Option<ScenarioPlayback> {
        self.get(id).map(|s| ScenarioPlayback::new(s.clone()))
    }
}

/// Scenario info for listing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScenarioInfo {
    pub id: String,
    pub name: String,
    pub description: String,
    pub spin_count: usize,
    pub loop_mode: LoopMode,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scenario_creation() {
        let mut scenario = DemoScenario::new("test", "Test Scenario");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.add_spin(ScriptedOutcome::SmallWin { ratio: 5.0 });
        assert_eq!(scenario.len(), 2);
    }

    #[test]
    fn test_playback_once() {
        let mut scenario = DemoScenario::new("test", "Test");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.add_spin(ScriptedOutcome::SmallWin { ratio: 2.0 });
        scenario.loop_mode = LoopMode::Once;

        let mut playback = ScenarioPlayback::new(scenario);

        assert!(playback.next().is_some());
        assert!(playback.next().is_some());
        assert!(playback.next().is_none());
        assert!(playback.is_complete());
    }

    #[test]
    fn test_playback_loop() {
        let mut scenario = DemoScenario::new("test", "Test");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.loop_mode = LoopMode::Count(3);

        let mut playback = ScenarioPlayback::new(scenario);

        // Should loop 3 times
        for _ in 0..3 {
            assert!(playback.next().is_some());
        }
        assert!(playback.is_complete());
    }

    #[test]
    fn test_registry_presets() {
        let registry = ScenarioRegistry::new();
        let presets = registry.list();

        // Should have built-in presets
        assert!(presets.contains(&"win_showcase"));
        assert!(presets.contains(&"free_spins_demo"));
        assert!(presets.contains(&"cascade_demo"));
    }

    #[test]
    fn test_registry_playback() {
        let registry = ScenarioRegistry::new();
        let playback = registry.create_playback("win_showcase");

        assert!(playback.is_some());
        let playback = playback.unwrap();
        assert!(!playback.scenario().is_empty());
    }

    // =========================================================================
    // BUG#63 — validate_against grid dimension tests
    // =========================================================================

    use crate::scenario::presets::win_showcase;

    /// Helper: build a GameModel with a specific grid size.
    fn model_with_grid(reels: u8, rows: u8) -> GameModel {
        use crate::config::GridSpec;
        GameModel::new("Test", "test").with_grid(GridSpec { reels, rows, paylines: 20 })
    }

    /// Helper: build a SpecificGrid outcome from a flat symbol list.
    /// `symbol_grid` is indexed as [reel][row].
    fn specific_grid_outcome(symbol_grid: Vec<Vec<u32>>) -> ScriptedOutcome {
        ScriptedOutcome::SpecificGrid { grid: symbol_grid }
    }

    #[test]
    fn test_validate_against_no_specific_grids_always_ok() {
        let model = model_with_grid(5, 3);
        let scenario = win_showcase(); // contains no SpecificGrid outcomes
        assert!(scenario.validate_against(&model).is_ok());
    }

    #[test]
    fn test_validate_against_correct_dimensions_ok() {
        let model = model_with_grid(5, 3);
        // Build a 5×3 grid (5 reels, 3 rows each)
        let grid: Vec<Vec<u32>> = (0..5).map(|_| vec![1, 2, 3]).collect();

        let mut scenario = DemoScenario::new("grid_test", "Grid Test");
        scenario.add_spin(specific_grid_outcome(grid));

        assert!(scenario.validate_against(&model).is_ok());
    }

    #[test]
    fn test_validate_against_wrong_reel_count_err() {
        let model = model_with_grid(5, 3);
        // Only 3 reels instead of 5
        let grid: Vec<Vec<u32>> = (0..3).map(|_| vec![1, 2, 3]).collect();

        let mut scenario = DemoScenario::new("grid_test", "Grid Test");
        scenario.add_spin(specific_grid_outcome(grid));

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(
                err,
                ScenarioValidationError::WrongReelCount {
                    spin_index: 0,
                    expected: 5,
                    got: 3
                }
            ),
            "unexpected error variant: {err}"
        );
    }

    #[test]
    fn test_validate_against_wrong_row_count_err() {
        let model = model_with_grid(5, 3);
        // Reel 2 has only 2 rows instead of 3
        let mut grid: Vec<Vec<u32>> = (0..5).map(|_| vec![1, 2, 3]).collect();
        grid[2] = vec![1, 2]; // reel 2 is short

        let mut scenario = DemoScenario::new("grid_test", "Grid Test");
        scenario.add_spin(specific_grid_outcome(grid));

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(
                err,
                ScenarioValidationError::WrongRowCount {
                    spin_index: 0,
                    reel_index: 2,
                    expected: 3,
                    got: 2
                }
            ),
            "unexpected error variant: {err}"
        );
    }

    #[test]
    fn test_validate_against_reports_correct_spin_index() {
        let model = model_with_grid(5, 3);
        let good_grid: Vec<Vec<u32>> = (0..5).map(|_| vec![1, 2, 3]).collect();
        // Bad grid at spin index 2 (6 reels instead of 5)
        let bad_grid: Vec<Vec<u32>> = (0..6).map(|_| vec![1, 2, 3]).collect();

        let mut scenario = DemoScenario::new("grid_test", "Grid Test");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.add_spin(specific_grid_outcome(good_grid));
        scenario.add_spin(specific_grid_outcome(bad_grid));

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(
                err,
                ScenarioValidationError::WrongReelCount {
                    spin_index: 2,
                    expected: 5,
                    got: 6
                }
            ),
            "unexpected error variant: {err}"
        );
    }

    #[test]
    fn test_validate_against_oversized_grid_err() {
        // Too many reels AND too many rows — reports the reel count first
        let model = model_with_grid(5, 3);
        let grid: Vec<Vec<u32>> = (0..7).map(|_| vec![1, 2, 3, 4]).collect(); // 7×4

        let mut scenario = DemoScenario::new("grid_test", "Grid Test");
        scenario.add_spin(specific_grid_outcome(grid));

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(
                err,
                ScenarioValidationError::WrongReelCount {
                    spin_index: 0,
                    expected: 5,
                    got: 7
                }
            ),
            "unexpected error variant: {err}"
        );
    }

    // =========================================================================
    // BUG#63 EXTENSION — coverage for non-grid outcomes (commit follows)
    // =========================================================================

    #[test]
    fn test_validate_empty_sequence_err() {
        let model = model_with_grid(5, 3);
        let scenario = DemoScenario::new("empty", "Empty");
        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err, ScenarioValidationError::EmptySequence),
            "unexpected error: {err}");
    }

    #[test]
    fn test_validate_unknown_symbol_id_err() {
        // StandardSymbolSet has ids 1..=13 — id 99 should not resolve.
        let model = model_with_grid(5, 3);
        // Reels of 3 cells, with one cell holding an unknown id.
        let mut grid: Vec<Vec<u32>> = (0..5).map(|_| vec![1, 2, 3]).collect();
        grid[2][1] = 99;
        let mut scenario = DemoScenario::new("unknown_sym", "Unknown Symbol");
        scenario.add_spin(specific_grid_outcome(grid));

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(err,
                ScenarioValidationError::UnknownSymbolId {
                    spin_index: 0, reel_index: 2, row_index: 1, symbol_id: 99
                }
            ),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn test_validate_nan_win_ratio_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("nan", "NaN Win");
        scenario.add_spin(ScriptedOutcome::BigWin { ratio: f64::NAN });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(err, ScenarioValidationError::InvalidWinRatio { spin_index: 0, variant: "BigWin", .. }),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn test_validate_negative_win_ratio_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("neg", "Negative Win");
        scenario.add_spin(ScriptedOutcome::SmallWin { ratio: -1.0 });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(
            matches!(err, ScenarioValidationError::InvalidWinRatio { spin_index: 0, variant: "SmallWin", .. }),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn test_validate_infinite_win_ratio_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("inf", "Infinite Win");
        scenario.add_spin(ScriptedOutcome::MegaWin { ratio: f64::INFINITY });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err, ScenarioValidationError::InvalidWinRatio { variant: "MegaWin", .. }),
            "unexpected error: {err}");
    }

    #[test]
    fn test_validate_zero_free_spin_count_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("zero_fs", "Zero Free Spins");
        scenario.add_spin(ScriptedOutcome::TriggerFreeSpins { count: 0, multiplier: 1.0 });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err,
            ScenarioValidationError::InvalidFreeSpinCount { count: 0, .. }),
            "unexpected: {err}");
    }

    #[test]
    fn test_validate_huge_free_spin_count_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("huge_fs", "Huge Free Spins");
        scenario.add_spin(ScriptedOutcome::TriggerFreeSpins {
            count: SCENARIO_MAX_FREE_SPINS + 1,
            multiplier: 1.0,
        });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err, ScenarioValidationError::InvalidFreeSpinCount { .. }),
            "unexpected: {err}");
    }

    #[test]
    fn test_validate_invalid_multiplier_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("bad_mult", "Bad Multiplier");
        scenario.add_spin(ScriptedOutcome::TriggerFreeSpins {
            count: 10,
            multiplier: f64::NEG_INFINITY,
        });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err,
            ScenarioValidationError::InvalidMultiplier { variant: "TriggerFreeSpins", .. }),
            "unexpected: {err}");
    }

    #[test]
    fn test_validate_huge_cascade_chain_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("huge_cas", "Huge Cascade");
        scenario.add_spin(ScriptedOutcome::CascadeChain {
            wins: SCENARIO_MAX_CASCADE_WINS + 1,
        });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err, ScenarioValidationError::InvalidCascadeWinCount { .. }),
            "unexpected: {err}");
    }

    #[test]
    fn test_validate_zero_cascade_chain_err() {
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("zero_cas", "Zero Cascade");
        scenario.add_spin(ScriptedOutcome::CascadeChain { wins: 0 });

        let err = scenario.validate_against(&model).unwrap_err();
        assert!(matches!(err, ScenarioValidationError::InvalidCascadeWinCount { wins: 0, .. }),
            "unexpected: {err}");
    }

    #[test]
    fn test_validate_lose_and_near_miss_pass_through() {
        // Outcomes with no numeric payload should always pass.
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("misc", "Misc");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.add_spin(ScriptedOutcome::TriggerHoldAndWin);
        scenario.add_spin(ScriptedOutcome::NearMiss { feature: "free_spins".into() });
        scenario.add_spin(ScriptedOutcome::TriggerJackpot { tier: "MINOR".into() });
        assert!(scenario.validate_against(&model).is_ok());
    }

    #[test]
    fn test_validate_valid_full_payload_ok() {
        // Sanity: a fully-loaded scenario with valid values for every numeric
        // payload passes. Catches regressions where the new validators reject
        // healthy data.
        let model = model_with_grid(5, 3);
        let mut scenario = DemoScenario::new("happy", "Happy Path");
        scenario.add_spin(ScriptedOutcome::Lose);
        scenario.add_spin(ScriptedOutcome::SmallWin { ratio: 5.0 });
        scenario.add_spin(ScriptedOutcome::TriggerFreeSpins { count: 10, multiplier: 2.0 });
        scenario.add_spin(ScriptedOutcome::CascadeChain { wins: 5 });
        // 5x3 grid using only standard symbols (1..=10 are regular)
        let grid: Vec<Vec<u32>> = (0..5).map(|i| vec![1 + i % 10, 2 + i % 10, 3 + i % 10]).collect();
        scenario.add_spin(specific_grid_outcome(grid));
        assert!(scenario.validate_against(&model).is_ok());
    }
}
