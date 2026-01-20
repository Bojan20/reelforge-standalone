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
//!
//! ## Built-in Presets
//!
//! - `win_showcase` — All win tiers from lose to ultra
//! - `free_spins_demo` — Free spins trigger and sequence
//! - `cascade_demo` — Cascade chain demonstration
//! - `jackpot_demo` — Jackpot wheel sequence
//! - `stress_test` — Rapid fire for testing

// TODO: Implement in Phase 3
// mod demo;
// mod outcome;
// mod playback;
// mod presets;

// pub use demo::*;
// pub use outcome::*;
// pub use playback::*;
// pub use presets::*;

// Placeholder types for now
use serde::{Deserialize, Serialize};

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
}
