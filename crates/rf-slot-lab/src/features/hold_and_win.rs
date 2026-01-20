//! Hold and Win Feature Chapter

use rf_stage::{FeatureType, Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

/// Hold and Win configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoldAndWinConfig {
    pub trigger_count: u8,
    pub initial_respins: u8,
    pub reset_respins_on_hit: bool,
    pub grid_size: u8,
}

impl Default for HoldAndWinConfig {
    fn default() -> Self {
        Self {
            trigger_count: 6,
            initial_respins: 3,
            reset_respins_on_hit: true,
            grid_size: 15,
        }
    }
}

/// Locked symbol information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LockedSymbol {
    pub position: u8,
    pub value: f64,
    pub symbol_type: HoldSymbolType,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HoldSymbolType {
    Normal,
    Mini,
    Minor,
    Major,
    Grand,
}

#[derive(Debug, Clone, Default)]
struct HoldAndWinState {
    is_active: bool,
    remaining_respins: u8,
    total_respins: u8,
    locked_symbols: Vec<LockedSymbol>,
    total_value: f64,
}

/// Hold and Win Feature Chapter
pub struct HoldAndWinChapter {
    config: HoldAndWinConfig,
    state: HoldAndWinState,
}

impl HoldAndWinChapter {
    pub fn new() -> Self {
        Self {
            config: HoldAndWinConfig::default(),
            state: HoldAndWinState::default(),
        }
    }

    pub fn with_config(config: HoldAndWinConfig) -> Self {
        Self {
            config,
            state: HoldAndWinState::default(),
        }
    }

    pub fn locked_count(&self) -> usize {
        self.state.locked_symbols.len()
    }

    pub fn fill_percentage(&self) -> f64 {
        self.state.locked_symbols.len() as f64 / self.config.grid_size as f64
    }
}

impl Default for HoldAndWinChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for HoldAndWinChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("hold_and_win")
    }

    fn name(&self) -> &str {
        "Hold and Win"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::HoldAndWin
    }

    fn description(&self) -> &str {
        "Lock symbols and respin to fill the grid"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(trigger) = config.get::<u8>("trigger_count") {
            self.config.trigger_count = trigger;
        }
        if let Some(respins) = config.get::<u8>("initial_respins") {
            self.config.initial_respins = respins;
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("trigger_count", self.config.trigger_count);
        config.set("initial_respins", self.config.initial_respins);
        config
    }

    fn reset_config(&mut self) {
        self.config = HoldAndWinConfig::default();
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
            "remaining_respins".to_string(),
            serde_json::Value::from(self.state.remaining_respins),
        );
        data.insert(
            "locked_count".to_string(),
            serde_json::Value::from(self.state.locked_symbols.len()),
        );

        FeatureSnapshot {
            feature_id: "hold_and_win".to_string(),
            is_active: self.state.is_active,
            current_step: self.state.total_respins as u32,
            total_steps: None,
            multiplier: 1.0,
            accumulated_win: self.state.total_value,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.total_respins = snapshot.current_step as u8;
        self.state.total_value = snapshot.accumulated_win;
        if let Some(remaining) = snapshot.data.get("remaining_respins").and_then(|v| v.as_u64()) {
            self.state.remaining_respins = remaining as u8;
        }
        Ok(())
    }

    fn can_activate(&self, context: &ActivationContext) -> bool {
        !self.state.is_active && context.scatter_count() >= self.config.trigger_count
    }

    fn activate(&mut self, _context: &ActivationContext) {
        self.state = HoldAndWinState {
            is_active: true,
            remaining_respins: self.config.initial_respins,
            total_respins: 0,
            locked_symbols: Vec::new(),
            total_value: 0.0,
        };
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
    }

    fn reset(&mut self) {
        self.state = HoldAndWinState::default();
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        if !self.state.is_active {
            return FeatureResult::inactive();
        }

        self.state.total_respins += 1;
        let new_symbols_landed = context.accumulated_win > 0.0;

        if new_symbols_landed {
            self.state.total_value += context.accumulated_win;
            if self.config.reset_respins_on_hit {
                self.state.remaining_respins = self.config.initial_respins;
            }
        } else {
            self.state.remaining_respins = self.state.remaining_respins.saturating_sub(1);
        }

        let feature_ends =
            self.state.remaining_respins == 0 || self.fill_percentage() >= 1.0;

        if feature_ends {
            FeatureResult::complete(self.state.total_value)
        } else {
            FeatureResult::continue_with(if new_symbols_landed {
                context.accumulated_win
            } else {
                0.0
            })
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

        let timestamp = timing.advance(300.0);
        vec![StageEvent::new(
            Stage::FeatureStep {
                step_index: self.state.total_respins as u32,
                steps_remaining: Some(self.state.remaining_respins as u32),
                current_multiplier: 1.0,
            },
            timestamp,
        )]
    }

    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.feature_enter();
        vec![StageEvent::new(
            Stage::FeatureEnter {
                feature_type: FeatureType::HoldAndSpin,
                total_steps: None,
                multiplier: 1.0,
            },
            timestamp,
        )]
    }

    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(1000.0);
        vec![StageEvent::new(
            Stage::FeatureExit {
                total_win: self.state.total_value,
            },
            timestamp,
        )]
    }

    fn stage_types(&self) -> Vec<&'static str> {
        vec!["FEATURE_ENTER", "HOLD_SYMBOL_LAND", "RESPIN", "FEATURE_EXIT"]
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
    fn test_hold_and_win_creation() {
        let chapter = HoldAndWinChapter::new();
        assert_eq!(chapter.id().as_str(), "hold_and_win");
        assert_eq!(chapter.category(), FeatureCategory::HoldAndWin);
    }

    #[test]
    fn test_hold_and_win_activation() {
        let mut chapter = HoldAndWinChapter::new();
        let context = ActivationContext::new(6, 1.0);

        assert!(chapter.can_activate(&context));
        chapter.activate(&context);
        assert!(chapter.is_active());
        assert_eq!(chapter.state.remaining_respins, 3);
    }
}
