//! Free Spins Feature Chapter
//!
//! Implements the classic free spins bonus feature with configurable:
//! - Spin count (fixed or range)
//! - Multiplier (fixed or progressive)
//! - Retrigger capability

use rf_stage::{FeatureType, Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Free Spins configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FreeSpinsConfig {
    /// Minimum spins awarded
    pub min_spins: u32,
    /// Maximum spins awarded
    pub max_spins: u32,
    /// Base multiplier
    pub base_multiplier: f64,
    /// Multiplier increment per spin (for progressive)
    pub multiplier_increment: f64,
    /// Maximum multiplier cap
    pub max_multiplier: f64,
    /// Can retrigger during feature
    pub can_retrigger: bool,
    /// Scatters needed to retrigger
    pub retrigger_scatter_count: u8,
    /// Extra spins on retrigger
    pub retrigger_spins: u32,
}

impl Default for FreeSpinsConfig {
    fn default() -> Self {
        Self {
            min_spins: 8,
            max_spins: 15,
            base_multiplier: 1.0,
            multiplier_increment: 0.0,
            max_multiplier: 10.0,
            can_retrigger: true,
            retrigger_scatter_count: 3,
            retrigger_spins: 5,
        }
    }
}

impl FreeSpinsConfig {
    /// High volatility preset
    pub fn high_volatility() -> Self {
        Self {
            min_spins: 5,
            max_spins: 25,
            base_multiplier: 2.0,
            multiplier_increment: 1.0,
            max_multiplier: 15.0,
            can_retrigger: true,
            retrigger_scatter_count: 3,
            retrigger_spins: 10,
        }
    }

    /// Progressive multiplier preset
    pub fn progressive() -> Self {
        Self {
            min_spins: 10,
            max_spins: 10,
            base_multiplier: 1.0,
            multiplier_increment: 1.0,
            max_multiplier: 10.0,
            can_retrigger: false,
            retrigger_scatter_count: 3,
            retrigger_spins: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Free Spins runtime state
#[derive(Debug, Clone, Default)]
struct FreeSpinsState {
    is_active: bool,
    total_spins: u32,
    remaining_spins: u32,
    current_spin: u32,
    current_multiplier: f64,
    total_win: f64,
    retrigger_count: u32,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHAPTER IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Free Spins Feature Chapter
pub struct FreeSpinsChapter {
    config: FreeSpinsConfig,
    state: FreeSpinsState,
}

impl FreeSpinsChapter {
    pub fn new() -> Self {
        Self {
            config: FreeSpinsConfig::default(),
            state: FreeSpinsState::default(),
        }
    }

    pub fn with_config(config: FreeSpinsConfig) -> Self {
        Self {
            config,
            state: FreeSpinsState::default(),
        }
    }

    fn calculate_initial_spins(&self, scatter_count: u8) -> u32 {
        let base = self.config.min_spins;
        let extra_per_scatter = (self.config.max_spins - self.config.min_spins) / 3;
        let bonus = (scatter_count.saturating_sub(3) as u32) * extra_per_scatter;
        (base + bonus).min(self.config.max_spins)
    }

    fn increment_multiplier(&mut self) {
        if self.config.multiplier_increment > 0.0 {
            self.state.current_multiplier = (self.state.current_multiplier
                + self.config.multiplier_increment)
                .min(self.config.max_multiplier);
        }
    }
}

impl Default for FreeSpinsChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for FreeSpinsChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("free_spins")
    }

    fn name(&self) -> &str {
        "Free Spins"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::FreeSpins
    }

    fn description(&self) -> &str {
        "Classic free spins bonus with optional multipliers and retriggers"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(min) = config.get::<u32>("min_spins") {
            self.config.min_spins = min;
        }
        if let Some(max) = config.get::<u32>("max_spins") {
            self.config.max_spins = max;
        }
        if let Some(mult) = config.get::<f64>("multiplier") {
            self.config.base_multiplier = mult;
        }
        if let Some(retrigger) = config.get::<bool>("can_retrigger") {
            self.config.can_retrigger = retrigger;
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("min_spins", self.config.min_spins);
        config.set("max_spins", self.config.max_spins);
        config.set("multiplier", self.config.base_multiplier);
        config.set("can_retrigger", self.config.can_retrigger);
        config
    }

    fn reset_config(&mut self) {
        self.config = FreeSpinsConfig::default();
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
            "total_spins".to_string(),
            serde_json::Value::from(self.state.total_spins),
        );
        data.insert(
            "remaining_spins".to_string(),
            serde_json::Value::from(self.state.remaining_spins),
        );
        data.insert(
            "retrigger_count".to_string(),
            serde_json::Value::from(self.state.retrigger_count),
        );

        FeatureSnapshot {
            feature_id: "free_spins".to_string(),
            is_active: self.state.is_active,
            current_step: self.state.current_spin,
            total_steps: Some(self.state.total_spins),
            multiplier: self.state.current_multiplier,
            accumulated_win: self.state.total_win,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.current_spin = snapshot.current_step;
        self.state.total_spins = snapshot.total_steps.unwrap_or(0);
        self.state.current_multiplier = snapshot.multiplier;
        self.state.total_win = snapshot.accumulated_win;

        if let Some(remaining) = snapshot.data.get("remaining_spins").and_then(|v| v.as_u64()) {
            self.state.remaining_spins = remaining as u32;
        }
        if let Some(retriggers) = snapshot.data.get("retrigger_count").and_then(|v| v.as_u64()) {
            self.state.retrigger_count = retriggers as u32;
        }

        Ok(())
    }

    fn can_activate(&self, context: &ActivationContext) -> bool {
        !self.state.is_active && context.scatter_count() >= 3
    }

    fn activate(&mut self, context: &ActivationContext) {
        let spins = self.calculate_initial_spins(context.scatter_count());

        self.state = FreeSpinsState {
            is_active: true,
            total_spins: spins,
            remaining_spins: spins,
            current_spin: 0,
            current_multiplier: self.config.base_multiplier,
            total_win: 0.0,
            retrigger_count: 0,
        };
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
    }

    fn reset(&mut self) {
        self.state = FreeSpinsState::default();
    }

    fn pre_spin(&mut self, _context: &SpinContext) {
        if self.state.is_active {
            self.state.current_spin += 1;
        }
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        if !self.state.is_active {
            return FeatureResult::inactive();
        }

        // Apply multiplier to win (use accumulated_win as base)
        let base_win = context.accumulated_win;
        let multiplied_win = base_win * self.state.current_multiplier;
        self.state.total_win += multiplied_win;

        // Increment multiplier for progressive
        self.increment_multiplier();

        // Decrement remaining
        self.state.remaining_spins = self.state.remaining_spins.saturating_sub(1);

        // Check if feature is complete
        if self.state.remaining_spins == 0 {
            FeatureResult::complete(multiplied_win).with_multiplier(self.state.current_multiplier)
        } else {
            FeatureResult::continue_with(multiplied_win)
                .with_multiplier(self.state.current_multiplier)
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

        let timestamp = timing.advance(100.0);
        vec![StageEvent::new(
            Stage::FeatureStep {
                step_index: self.state.current_spin,
                steps_remaining: Some(self.state.remaining_spins),
                current_multiplier: self.state.current_multiplier,
            },
            timestamp,
        )]
    }

    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.feature_enter();
        vec![StageEvent::new(
            Stage::FeatureEnter {
                feature_type: FeatureType::FreeSpins,
                total_steps: Some(self.state.total_spins),
                multiplier: self.config.base_multiplier,
            },
            timestamp,
        )]
    }

    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(1000.0);
        vec![StageEvent::new(
            Stage::FeatureExit {
                total_win: self.state.total_win,
            },
            timestamp,
        )]
    }

    fn stage_types(&self) -> Vec<&'static str> {
        vec!["FEATURE_ENTER", "FEATURE_STEP", "FEATURE_EXIT", "RETRIGGER"]
    }

    fn info(&self) -> FeatureInfo {
        FeatureInfo {
            id: self.id(),
            name: self.name().to_string(),
            category: self.category(),
            description: format!(
                "{} ({}-{} spins, {}x multiplier)",
                self.description(),
                self.config.min_spins,
                self.config.max_spins,
                self.config.base_multiplier
            ),
            is_active: self.state.is_active,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_free_spins_creation() {
        let chapter = FreeSpinsChapter::new();
        assert_eq!(chapter.id().as_str(), "free_spins");
        assert_eq!(chapter.category(), FeatureCategory::FreeSpins);
        assert!(!chapter.is_active());
    }

    #[test]
    fn test_free_spins_activation() {
        let mut chapter = FreeSpinsChapter::new();
        let context = ActivationContext::new(3, 1.0);

        assert!(chapter.can_activate(&context));
        chapter.activate(&context);
        assert!(chapter.is_active());
        assert_eq!(chapter.state.remaining_spins, 8); // min_spins default
    }

    #[test]
    fn test_free_spins_snapshot_restore() {
        let mut chapter = FreeSpinsChapter::new();
        chapter.activate(&ActivationContext::new(3, 1.0));
        chapter.state.current_spin = 3;
        chapter.state.remaining_spins = 5;

        let snapshot = chapter.snapshot();

        let mut chapter2 = FreeSpinsChapter::new();
        chapter2.restore(&snapshot).unwrap();

        assert_eq!(chapter2.state.current_spin, 3);
        assert_eq!(chapter2.state.remaining_spins, 5);
        assert!(chapter2.is_active());
    }
}
