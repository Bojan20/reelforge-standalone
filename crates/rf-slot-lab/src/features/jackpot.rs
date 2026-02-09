//! Jackpot Feature Chapter

use rf_stage::{JackpotTier, Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

/// Jackpot tier configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JackpotTierConfig {
    pub name: String,
    pub seed: f64,
    pub contribution_rate: f64,
    pub cap: f64,
    pub is_progressive: bool,
    pub trigger_probability: f64,
}

impl JackpotTierConfig {
    pub fn mini() -> Self {
        Self {
            name: "Mini".to_string(),
            seed: 50.0,
            contribution_rate: 0.005,
            cap: 500.0,
            is_progressive: true,
            trigger_probability: 0.001,
        }
    }

    pub fn minor() -> Self {
        Self {
            name: "Minor".to_string(),
            seed: 200.0,
            contribution_rate: 0.003,
            cap: 2000.0,
            is_progressive: true,
            trigger_probability: 0.0005,
        }
    }

    pub fn major() -> Self {
        Self {
            name: "Major".to_string(),
            seed: 1000.0,
            contribution_rate: 0.002,
            cap: 10000.0,
            is_progressive: true,
            trigger_probability: 0.0001,
        }
    }

    pub fn grand() -> Self {
        Self {
            name: "Grand".to_string(),
            seed: 10000.0,
            contribution_rate: 0.001,
            cap: 0.0,
            is_progressive: true,
            trigger_probability: 0.00001,
        }
    }
}

/// Jackpot system configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JackpotConfig {
    pub tiers: Vec<JackpotTierConfig>,
    pub trigger_symbol: u32,
    pub trigger_count: u8,
}

impl Default for JackpotConfig {
    fn default() -> Self {
        Self {
            tiers: vec![
                JackpotTierConfig::mini(),
                JackpotTierConfig::minor(),
                JackpotTierConfig::major(),
                JackpotTierConfig::grand(),
            ],
            trigger_symbol: 0,
            trigger_count: 5,
        }
    }
}

#[derive(Debug, Clone, Default)]
struct JackpotState {
    is_active: bool,
    current_values: Vec<f64>,
    won_tier: Option<usize>,
    won_amount: f64,
    total_contributions: f64,
}

/// Jackpot Feature Chapter
pub struct JackpotChapter {
    config: JackpotConfig,
    state: JackpotState,
}

impl JackpotChapter {
    pub fn new() -> Self {
        let config = JackpotConfig::default();
        let current_values = config.tiers.iter().map(|t| t.seed).collect();
        Self {
            config,
            state: JackpotState {
                current_values,
                ..Default::default()
            },
        }
    }

    pub fn with_config(config: JackpotConfig) -> Self {
        let current_values = config.tiers.iter().map(|t| t.seed).collect();
        Self {
            config,
            state: JackpotState {
                current_values,
                ..Default::default()
            },
        }
    }

    pub fn get_value(&self, tier: usize) -> f64 {
        self.state.current_values.get(tier).copied().unwrap_or(0.0)
    }

    pub fn contribute(&mut self, bet: f64) {
        for (i, tier_config) in self.config.tiers.iter().enumerate() {
            if tier_config.is_progressive {
                let contribution = bet * tier_config.contribution_rate;
                if let Some(value) = self.state.current_values.get_mut(i) {
                    *value += contribution;
                    if tier_config.cap > 0.0 && *value > tier_config.cap {
                        *value = tier_config.cap;
                    }
                }
                self.state.total_contributions += contribution;
            }
        }
    }

    fn check_random_trigger(&self, roll: f64) -> Option<usize> {
        let mut cumulative = 0.0;
        for (i, tier) in self.config.tiers.iter().enumerate() {
            cumulative += tier.trigger_probability;
            if roll < cumulative {
                return Some(i);
            }
        }
        None
    }

    fn award_jackpot(&mut self, tier: usize) -> f64 {
        let amount = self.state.current_values.get(tier).copied().unwrap_or(0.0);
        self.state.won_tier = Some(tier);
        self.state.won_amount = amount;

        if let Some(tier_config) = self.config.tiers.get(tier) {
            if let Some(value) = self.state.current_values.get_mut(tier) {
                *value = tier_config.seed;
            }
        }

        amount
    }

    fn tier_to_enum(&self, tier: usize) -> JackpotTier {
        match tier {
            0 => JackpotTier::Mini,
            1 => JackpotTier::Minor,
            2 => JackpotTier::Major,
            3 => JackpotTier::Grand,
            _ => JackpotTier::Custom(tier as u32),
        }
    }
}

impl Default for JackpotChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for JackpotChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("jackpot")
    }

    fn name(&self) -> &str {
        "Jackpot"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::Jackpot
    }

    fn description(&self) -> &str {
        "Progressive jackpot system with multiple tiers"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(trigger) = config.get::<u8>("trigger_count") {
            self.config.trigger_count = trigger;
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("trigger_count", self.config.trigger_count);
        config.set("tier_count", self.config.tiers.len());
        config
    }

    fn reset_config(&mut self) {
        self.config = JackpotConfig::default();
        self.state.current_values = self.config.tiers.iter().map(|t| t.seed).collect();
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
            "current_values".to_string(),
            serde_json::to_value(&self.state.current_values).unwrap_or_default(),
        );
        data.insert(
            "total_contributions".to_string(),
            serde_json::Value::from(self.state.total_contributions),
        );

        FeatureSnapshot {
            feature_id: "jackpot".to_string(),
            is_active: self.state.is_active,
            current_step: 0,
            total_steps: None,
            multiplier: 1.0,
            accumulated_win: self.state.won_amount,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.won_amount = snapshot.accumulated_win;

        if let Some(values) = snapshot.data.get("current_values") {
            if let Ok(v) = serde_json::from_value::<Vec<f64>>(values.clone()) {
                self.state.current_values = v;
            }
        }
        if let Some(contrib) = snapshot
            .data
            .get("total_contributions")
            .and_then(|v| v.as_f64())
        {
            self.state.total_contributions = contrib;
        }

        Ok(())
    }

    fn can_activate(&self, _context: &ActivationContext) -> bool {
        !self.state.is_active
    }

    fn activate(&mut self, _context: &ActivationContext) {
        self.state.is_active = true;
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
        self.state.won_tier = None;
        self.state.won_amount = 0.0;
    }

    fn reset(&mut self) {
        self.state = JackpotState {
            current_values: self.config.tiers.iter().map(|t| t.seed).collect(),
            ..Default::default()
        };
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        self.contribute(context.bet);

        let trigger_roll = context.random;
        if let Some(tier) = self.check_random_trigger(trigger_roll) {
            let amount = self.award_jackpot(tier);
            self.state.is_active = true;

            return FeatureResult::complete(amount)
                .with_data("jackpot_tier", serde_json::Value::from(tier));
        }

        FeatureResult::inactive()
    }

    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        if !self.state.is_active || self.state.won_tier.is_none() {
            return Vec::new();
        }

        let tier = self.state.won_tier.unwrap();
        let tier_enum = self.tier_to_enum(tier);
        let amount = self.state.won_amount;
        let mut events = Vec::with_capacity(6);

        // P1.5: Expanded Jackpot Audio Sequence
        // Industry standard: multi-layer dramatic sequence

        // 1. JACKPOT_TRIGGER (500ms) - Alert tone
        let trigger_time = timing.advance(500.0);
        events.push(StageEvent::new(
            Stage::JackpotTrigger {
                tier: tier_enum.clone(),
            },
            trigger_time,
        ));

        // 2. JACKPOT_BUILDUP (2000ms) - Rising tension
        let buildup_time = timing.advance(2000.0);
        events.push(StageEvent::new(
            Stage::JackpotBuildup {
                tier: tier_enum.clone(),
            },
            buildup_time,
        ));

        // 3. JACKPOT_REVEAL (1000ms) - Tier reveal ("GRAND!")
        let reveal_time = timing.advance(1000.0);
        events.push(StageEvent::new(
            Stage::JackpotReveal {
                tier: tier_enum.clone(),
                amount,
            },
            reveal_time,
        ));

        // 4. JACKPOT_PRESENT (5000ms) - Main fanfare + amount display
        let present_time = timing.advance(5000.0);
        events.push(StageEvent::new(
            Stage::JackpotPresent {
                tier: tier_enum.clone(),
                amount,
            },
            present_time,
        ));

        // 5. JACKPOT_CELEBRATION (looping) - Plays until user dismisses
        let celebration_time = timing.advance(500.0);
        events.push(StageEvent::new(
            Stage::JackpotCelebration {
                tier: tier_enum.clone(),
                amount,
            },
            celebration_time,
        ));

        // 6. JACKPOT_END - Will be triggered when user dismisses
        // Note: This stage is typically triggered by user interaction,
        // but we include it in the sequence for completeness
        let end_time = timing.advance(1000.0);
        events.push(StageEvent::new(Stage::JackpotEnd, end_time));

        events
    }

    fn generate_activation_stages(&self, _timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        Vec::new()
    }

    fn generate_deactivation_stages(&self, _timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        Vec::new()
    }

    fn stage_types(&self) -> Vec<&'static str> {
        // P1.5: Full jackpot audio sequence
        vec![
            "JACKPOT_TRIGGER",     // Alert tone (500ms)
            "JACKPOT_BUILDUP",     // Rising tension (2000ms)
            "JACKPOT_REVEAL",      // Tier reveal (1000ms)
            "JACKPOT_PRESENT",     // Main fanfare (5000ms)
            "JACKPOT_CELEBRATION", // Looping celebration
            "JACKPOT_END",         // Fade out
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
    fn test_jackpot_creation() {
        let chapter = JackpotChapter::new();
        assert_eq!(chapter.id().as_str(), "jackpot");
        assert_eq!(chapter.config.tiers.len(), 4);
    }

    #[test]
    fn test_jackpot_contribution() {
        let mut chapter = JackpotChapter::new();
        let initial_mini = chapter.get_value(0);
        chapter.contribute(100.0);
        assert!(chapter.get_value(0) > initial_mini);
    }
}
