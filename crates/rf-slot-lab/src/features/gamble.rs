//! Gamble/Risk Feature Chapter

use rf_stage::{BonusChoiceType, GambleResult, Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

/// Gamble game type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GambleType {
    /// Red/Black card guess (50/50)
    CardColor,
    /// Card suit guess (25% chance)
    CardSuit,
    /// Coin flip
    CoinFlip,
    /// Ladder climb
    Ladder,
}

impl Default for GambleType {
    fn default() -> Self {
        Self::CardColor
    }
}

/// Gamble configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GambleConfig {
    pub gamble_type: GambleType,
    pub max_attempts: u8,
    pub win_multiplier: f64,
    pub max_win_cap: f64,
}

impl Default for GambleConfig {
    fn default() -> Self {
        Self {
            gamble_type: GambleType::CardColor,
            max_attempts: 5,
            win_multiplier: 2.0,
            max_win_cap: 10000.0,
        }
    }
}

/// Player's gamble choice
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GambleChoice {
    Red,
    Black,
    Hearts,
    Diamonds,
    Clubs,
    Spades,
    Heads,
    Tails,
    Higher,
    Lower,
}

/// Gamble outcome
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GambleOutcome {
    Win,
    Lose,
    Draw,
}

#[derive(Debug, Clone, Default)]
struct GambleState {
    is_active: bool,
    original_win: f64,
    current_win: f64,
    attempts_used: u8,
    last_outcome: Option<GambleOutcome>,
}

/// Gamble Feature Chapter
pub struct GambleChapter {
    config: GambleConfig,
    state: GambleState,
}

impl GambleChapter {
    pub fn new() -> Self {
        Self {
            config: GambleConfig::default(),
            state: GambleState::default(),
        }
    }

    pub fn with_config(config: GambleConfig) -> Self {
        Self {
            config,
            state: GambleState::default(),
        }
    }

    fn determine_outcome(&self, roll: f64) -> GambleOutcome {
        let win_chance = match self.config.gamble_type {
            GambleType::CardColor | GambleType::CoinFlip => 0.5,
            GambleType::CardSuit => 0.25,
            GambleType::Ladder => 0.5,
        };

        if roll < win_chance {
            GambleOutcome::Win
        } else if roll < win_chance + 0.02 {
            // Small draw chance
            GambleOutcome::Draw
        } else {
            GambleOutcome::Lose
        }
    }

    fn gamble_type_to_choice_type(&self) -> BonusChoiceType {
        match self.config.gamble_type {
            GambleType::CardColor => BonusChoiceType::RedBlack,
            GambleType::CardSuit => BonusChoiceType::Suit,
            GambleType::CoinFlip => BonusChoiceType::HigherLower,
            GambleType::Ladder => BonusChoiceType::HigherLower,
        }
    }

    fn outcome_to_gamble_result(&self, outcome: GambleOutcome) -> GambleResult {
        match outcome {
            GambleOutcome::Win => GambleResult::Win,
            GambleOutcome::Lose => GambleResult::Lose,
            GambleOutcome::Draw => GambleResult::Draw,
        }
    }
}

impl Default for GambleChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for GambleChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("gamble")
    }

    fn name(&self) -> &str {
        "Gamble"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::Gamble
    }

    fn description(&self) -> &str {
        "Risk your winnings for a chance to double"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(max) = config.get::<u8>("max_attempts") {
            self.config.max_attempts = max;
        }
        if let Some(mult) = config.get::<f64>("win_multiplier") {
            self.config.win_multiplier = mult;
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("max_attempts", self.config.max_attempts);
        config.set("win_multiplier", self.config.win_multiplier);
        config
    }

    fn reset_config(&mut self) {
        self.config = GambleConfig::default();
    }

    fn state(&self) -> FeatureState {
        if self.state.is_active {
            FeatureState::Active
        } else {
            FeatureState::Inactive
        }
    }

    fn snapshot(&self) -> FeatureSnapshot {
        let mut data = std::collections::HashMap::new();
        data.insert(
            "original_win".to_string(),
            serde_json::Value::from(self.state.original_win),
        );
        data.insert(
            "attempts_used".to_string(),
            serde_json::Value::from(self.state.attempts_used),
        );

        FeatureSnapshot {
            feature_id: "gamble".to_string(),
            is_active: self.state.is_active,
            current_step: self.state.attempts_used as u32,
            total_steps: Some(self.config.max_attempts as u32),
            multiplier: self.config.win_multiplier,
            accumulated_win: self.state.current_win,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.attempts_used = snapshot.current_step as u8;
        self.state.current_win = snapshot.accumulated_win;

        if let Some(original) = snapshot.data.get("original_win").and_then(|v| v.as_f64()) {
            self.state.original_win = original;
        }
        Ok(())
    }

    fn can_activate(&self, context: &ActivationContext) -> bool {
        !self.state.is_active && context.bet > 0.0
    }

    fn activate(&mut self, context: &ActivationContext) {
        self.state = GambleState {
            is_active: true,
            original_win: context.bet, // Use bet as placeholder, actual win set via context
            current_win: context.bet,
            attempts_used: 0,
            last_outcome: None,
        };
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
    }

    fn reset(&mut self) {
        self.state = GambleState::default();
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        if !self.state.is_active {
            return FeatureResult::inactive();
        }

        let outcome = self.determine_outcome(context.random);
        self.state.last_outcome = Some(outcome);
        self.state.attempts_used += 1;

        match outcome {
            GambleOutcome::Win => {
                self.state.current_win *= self.config.win_multiplier;
                if self.state.current_win > self.config.max_win_cap {
                    self.state.current_win = self.config.max_win_cap;
                }

                // Check if max attempts reached
                if self.state.attempts_used >= self.config.max_attempts {
                    FeatureResult::complete(self.state.current_win)
                } else {
                    FeatureResult::continue_with(self.state.current_win)
                }
            }
            GambleOutcome::Lose => {
                self.state.current_win = 0.0;
                FeatureResult::complete(0.0)
            }
            GambleOutcome::Draw => {
                // Draw = keep current, can continue
                if self.state.attempts_used >= self.config.max_attempts {
                    FeatureResult::complete(self.state.current_win)
                } else {
                    FeatureResult::continue_with(self.state.current_win)
                }
            }
        }
    }

    fn post_spin(&mut self, _context: &SpinContext, result: &FeatureResult) {
        if !result.continues() {
            self.deactivate();
        }
    }

    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        if !self.state.is_active {
            return Vec::new();
        }

        let mut stages = Vec::new();

        // Choice stage
        let choice_ts = timing.advance(500.0);
        stages.push(StageEvent::new(
            Stage::GambleChoice {
                choice_type: self.gamble_type_to_choice_type(),
            },
            choice_ts,
        ));

        // Result stage (if we have an outcome)
        if let Some(outcome) = self.state.last_outcome {
            let result_ts = timing.advance(1000.0);
            stages.push(StageEvent::new(
                Stage::GambleResultStage {
                    result: self.outcome_to_gamble_result(outcome),
                    new_amount: self.state.current_win,
                },
                result_ts,
            ));
        }

        stages
    }

    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(500.0);
        vec![StageEvent::new(
            Stage::GambleStart {
                stake_amount: self.state.original_win,
            },
            timestamp,
        )]
    }

    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(500.0);
        vec![StageEvent::new(
            Stage::GambleEnd {
                collected_amount: self.state.current_win,
            },
            timestamp,
        )]
    }

    fn stage_types(&self) -> Vec<&'static str> {
        vec![
            "GAMBLE_START",
            "GAMBLE_CHOICE",
            "GAMBLE_RESULT",
            "GAMBLE_END",
        ]
    }

    fn info(&self) -> FeatureInfo {
        FeatureInfo {
            id: self.id(),
            name: self.name().to_string(),
            category: self.category(),
            description: self.description().to_string(),
            is_active: self.state.is_active,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gamble_creation() {
        let chapter = GambleChapter::new();
        assert_eq!(chapter.id().as_str(), "gamble");
        assert_eq!(chapter.category(), FeatureCategory::Gamble);
    }

    #[test]
    fn test_gamble_outcome_determination() {
        let chapter = GambleChapter::new();

        // Roll 0.3 should win (< 0.5)
        assert_eq!(chapter.determine_outcome(0.3), GambleOutcome::Win);

        // Roll 0.8 should lose (> 0.52)
        assert_eq!(chapter.determine_outcome(0.8), GambleOutcome::Lose);
    }
}
