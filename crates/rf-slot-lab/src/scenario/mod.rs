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
/// BUG#63 — Symbol arrays in `SpecificGrid` outcomes must match the game's
/// configured grid dimensions (reels × rows).
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
}

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
    /// Checks that every `SpecificGrid` outcome in the sequence has exactly
    /// `model.grid.reels` reels and exactly `model.grid.rows` rows per reel.
    ///
    /// Returns the first validation error found, or `Ok(())` if all spins are
    /// compatible with the model.  Call this after constructing a scenario from
    /// user input or deserialised data before handing it to `ScenarioPlayback`.
    ///
    /// # BUG#63
    /// Without this check a `SpecificGrid` with the wrong dimensions would be
    /// silently accepted and could cause out-of-bounds access or incorrect win
    /// evaluation downstream.
    pub fn validate_against(&self, model: &GameModel) -> Result<(), ScenarioValidationError> {
        let expected_reels = model.grid.reels as usize;
        let expected_rows = model.grid.rows as usize;

        for (spin_index, spin) in self.sequence.iter().enumerate() {
            if let ScriptedOutcome::SpecificGrid { grid } = &spin.outcome {
                // Check reel count
                if grid.len() != expected_reels {
                    return Err(ScenarioValidationError::WrongReelCount {
                        spin_index,
                        expected: expected_reels,
                        got: grid.len(),
                    });
                }

                // Check row count per reel
                for (reel_index, reel) in grid.iter().enumerate() {
                    if reel.len() != expected_rows {
                        return Err(ScenarioValidationError::WrongRowCount {
                            spin_index,
                            reel_index,
                            expected: expected_rows,
                            got: reel.len(),
                        });
                    }
                }
            }
        }

        Ok(())
    }
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
}
