//! Cascades/Tumble Feature Chapter

use rf_stage::{Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

/// Cascade configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CascadeConfig {
    /// Maximum cascade depth (0 = unlimited)
    pub max_depth: u8,
    /// Multiplier progression per cascade [1x, 2x, 3x, ...]
    pub multiplier_progression: Vec<f64>,
    /// How winning symbols are removed
    pub remove_mode: CascadeRemoveMode,
}

/// How winning symbols are removed in cascade
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CascadeRemoveMode {
    /// Only winning symbols removed
    WinningOnly,
    /// Entire winning reels cleared
    WholeReel,
    /// Winning symbols + adjacent
    WithAdjacent,
}

impl Default for CascadeConfig {
    fn default() -> Self {
        Self {
            max_depth: 0, // Unlimited
            multiplier_progression: vec![1.0, 2.0, 3.0, 5.0, 8.0, 10.0],
            remove_mode: CascadeRemoveMode::WinningOnly,
        }
    }
}

#[derive(Debug, Clone, Default)]
struct CascadeState {
    is_active: bool,
    current_step: u32,
    total_win: f64,
    current_multiplier: f64,
    peak_multiplier: f64,
}

/// Cascades Feature Chapter
pub struct CascadesChapter {
    config: CascadeConfig,
    state: CascadeState,
}

impl CascadesChapter {
    pub fn new() -> Self {
        Self {
            config: CascadeConfig::default(),
            state: CascadeState::default(),
        }
    }

    pub fn with_config(config: CascadeConfig) -> Self {
        Self {
            config,
            state: CascadeState::default(),
        }
    }

    fn get_multiplier_for_step(&self, step: u32) -> f64 {
        let idx = step as usize;
        if idx < self.config.multiplier_progression.len() {
            self.config.multiplier_progression[idx]
        } else {
            // Use last multiplier for steps beyond progression
            self.config
                .multiplier_progression
                .last()
                .copied()
                .unwrap_or(1.0)
        }
    }
}

impl Default for CascadesChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for CascadesChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("cascades")
    }

    fn name(&self) -> &str {
        "Cascades"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::Cascade
    }

    fn description(&self) -> &str {
        "Tumbling reels with multiplier progression"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(depth) = config.get::<u8>("max_depth") {
            self.config.max_depth = depth;
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("max_depth", self.config.max_depth);
        config
    }

    fn reset_config(&mut self) {
        self.config = CascadeConfig::default();
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
            "peak_multiplier".to_string(),
            serde_json::Value::from(self.state.peak_multiplier),
        );

        FeatureSnapshot {
            feature_id: "cascades".to_string(),
            is_active: self.state.is_active,
            current_step: self.state.current_step,
            total_steps: None,
            multiplier: self.state.current_multiplier,
            accumulated_win: self.state.total_win,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.current_step = snapshot.current_step;
        self.state.current_multiplier = snapshot.multiplier;
        self.state.total_win = snapshot.accumulated_win;

        if let Some(peak) = snapshot.data.get("peak_multiplier").and_then(|v| v.as_f64()) {
            self.state.peak_multiplier = peak;
        }
        Ok(())
    }

    fn can_activate(&self, context: &ActivationContext) -> bool {
        // Cascades activate on any win
        !self.state.is_active && context.bet > 0.0
    }

    fn activate(&mut self, _context: &ActivationContext) {
        self.state = CascadeState {
            is_active: true,
            current_step: 0,
            total_win: 0.0,
            current_multiplier: self.get_multiplier_for_step(0),
            peak_multiplier: 1.0,
        };
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
    }

    fn reset(&mut self) {
        self.state = CascadeState::default();
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        if !self.state.is_active {
            return FeatureResult::inactive();
        }

        let base_win = context.accumulated_win;

        // No win = cascade ends
        if base_win <= 0.0 {
            return FeatureResult::complete(0.0)
                .with_multiplier(self.state.peak_multiplier)
                .with_data(
                    "cascade_depth",
                    serde_json::Value::from(self.state.current_step),
                );
        }

        // Apply multiplier
        let multiplied_win = base_win * self.state.current_multiplier;
        self.state.total_win += multiplied_win;

        // Track peak multiplier
        if self.state.current_multiplier > self.state.peak_multiplier {
            self.state.peak_multiplier = self.state.current_multiplier;
        }

        // Advance step
        self.state.current_step += 1;
        self.state.current_multiplier = self.get_multiplier_for_step(self.state.current_step);

        // Check max depth
        if self.config.max_depth > 0 && self.state.current_step >= self.config.max_depth as u32 {
            return FeatureResult::complete(multiplied_win)
                .with_multiplier(self.state.current_multiplier);
        }

        FeatureResult::continue_with(multiplied_win).with_multiplier(self.state.current_multiplier)
    }

    fn post_spin(&mut self, _context: &SpinContext, result: &FeatureResult) {
        if !result.continues() {
            self.deactivate();
        }
    }

    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        if !self.state.is_active || self.state.current_step == 0 {
            return Vec::new();
        }

        let timestamp = timing.cascade_step();
        vec![StageEvent::new(
            Stage::CascadeStep {
                step_index: self.state.current_step - 1,
                multiplier: self.state.current_multiplier,
            },
            timestamp,
        )]
    }

    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(200.0);
        vec![StageEvent::new(Stage::CascadeStart, timestamp)]
    }

    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(500.0);
        vec![StageEvent::new(
            Stage::CascadeEnd {
                total_steps: self.state.current_step,
                total_win: self.state.total_win,
            },
            timestamp,
        )]
    }

    fn stage_types(&self) -> Vec<&'static str> {
        vec!["CASCADE_START", "CASCADE_STEP", "CASCADE_END"]
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
    fn test_cascades_creation() {
        let chapter = CascadesChapter::new();
        assert_eq!(chapter.id().as_str(), "cascades");
        assert_eq!(chapter.category(), FeatureCategory::Cascade);
    }

    #[test]
    fn test_cascade_multiplier_progression() {
        let chapter = CascadesChapter::new();
        assert!((chapter.get_multiplier_for_step(0) - 1.0).abs() < 0.001);
        assert!((chapter.get_multiplier_for_step(1) - 2.0).abs() < 0.001);
        assert!((chapter.get_multiplier_for_step(2) - 3.0).abs() < 0.001);
    }
}
