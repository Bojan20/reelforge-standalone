//! Pick Bonus Feature Chapter
//!
//! Classic "pick an object to reveal a prize" bonus game:
//! - Multiple hidden items (boxes, eggs, cards, treasure chests)
//! - Each item contains a prize (coins, multiplier, end game)
//! - Player picks until end trigger or all items revealed
//!
//! Used for secondary bonus games, jackpot reveals, etc.

use rf_stage::{Stage, StageEvent};
use serde::{Deserialize, Serialize};

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, ConfigError, FeatureCategory, FeatureChapter, FeatureConfig, FeatureId,
    FeatureInfo, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
};

/// Pick bonus game style
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PickBonusStyle {
    /// Pick boxes with prizes
    Boxes,
    /// Pick golden eggs
    Eggs,
    /// Flip cards to reveal prizes
    Cards,
    /// Open treasure chests
    Treasure,
    /// Custom themed picks
    Custom,
}

impl Default for PickBonusStyle {
    fn default() -> Self {
        Self::Boxes
    }
}

/// Prize type that can be revealed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PrizeType {
    /// Fixed coin value
    Coins(f64),
    /// Multiplier applied to base win
    Multiplier(f64),
    /// Extra picks
    ExtraPicks(u8),
    /// Jackpot tier (0=Mini, 1=Minor, 2=Major, 3=Grand)
    Jackpot(u8),
    /// End game / Pooper
    EndGame,
    /// Collect and exit with current winnings
    Collect,
}

impl PrizeType {
    pub fn is_end_game(&self) -> bool {
        matches!(self, PrizeType::EndGame | PrizeType::Collect)
    }
}

/// A single pickable item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PickItem {
    pub index: u8,
    pub prize: PrizeType,
    pub revealed: bool,
}

/// Pick bonus configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PickBonusConfig {
    pub style: PickBonusStyle,
    pub total_items: u8,
    pub end_game_count: u8,
    pub base_coin_values: Vec<f64>,
    pub multiplier_values: Vec<f64>,
    pub jackpot_chance: f64,
}

impl Default for PickBonusConfig {
    fn default() -> Self {
        Self {
            style: PickBonusStyle::Boxes,
            total_items: 12,
            end_game_count: 3,
            base_coin_values: vec![10.0, 25.0, 50.0, 100.0, 250.0, 500.0],
            multiplier_values: vec![2.0, 3.0, 5.0, 10.0],
            jackpot_chance: 0.02,
        }
    }
}

#[derive(Debug, Clone, Default)]
struct PickBonusState {
    is_active: bool,
    items: Vec<PickItem>,
    picks_made: u8,
    extra_picks: u8,
    total_win: f64,
    multiplier: f64,
    jackpots_won: Vec<u8>,
    last_pick_index: Option<u8>,
}

/// Pick Bonus Feature Chapter
pub struct PickBonusChapter {
    config: PickBonusConfig,
    state: PickBonusState,
}

impl PickBonusChapter {
    pub fn new() -> Self {
        Self {
            config: PickBonusConfig::default(),
            state: PickBonusState::default(),
        }
    }

    pub fn with_config(config: PickBonusConfig) -> Self {
        Self {
            config,
            state: PickBonusState::default(),
        }
    }

    /// Get current items (for UI)
    pub fn items(&self) -> &[PickItem] {
        &self.state.items
    }

    /// Get total win accumulated
    pub fn total_win(&self) -> f64 {
        self.state.total_win
    }

    /// Get current multiplier
    pub fn multiplier(&self) -> f64 {
        self.state.multiplier
    }

    /// Get picks remaining (including extra picks)
    pub fn picks_remaining(&self) -> u8 {
        let revealed = self.state.items.iter().filter(|i| i.revealed).count() as u8;
        let end_games_hit = self.state.items.iter()
            .filter(|i| i.revealed && i.prize.is_end_game())
            .count() as u8;

        if end_games_hit >= self.config.end_game_count {
            return 0;
        }

        let total_available = self.config.total_items - revealed;
        total_available.saturating_add(self.state.extra_picks)
    }

    /// Generate items based on config and randomness
    fn generate_items(&mut self, base_seed: f64, bet: f64) {
        use std::collections::HashSet;

        let mut items = Vec::with_capacity(self.config.total_items as usize);
        let mut used_indices: HashSet<u8> = HashSet::new();

        // Add end game items
        for i in 0..self.config.end_game_count {
            items.push(PickItem {
                index: i,
                prize: PrizeType::EndGame,
                revealed: false,
            });
            used_indices.insert(i);
        }

        // Add one collect
        let collect_idx = self.config.end_game_count;
        items.push(PickItem {
            index: collect_idx,
            prize: PrizeType::Collect,
            revealed: false,
        });
        used_indices.insert(collect_idx);

        // Fill remaining with prizes
        let remaining_count = self.config.total_items - self.config.end_game_count - 1;
        let mut seed = base_seed;

        for i in 0..remaining_count {
            seed = (seed * 1103515245.0 + 12345.0) % 2147483648.0;
            let normalized = seed / 2147483648.0;

            let idx = (self.config.end_game_count + 1 + i) as u8;
            let prize = if normalized < self.config.jackpot_chance {
                // Jackpot
                let tier = ((normalized * 4.0 / self.config.jackpot_chance) as u8).min(3);
                PrizeType::Jackpot(tier)
            } else if normalized < 0.1 {
                // Extra picks
                PrizeType::ExtraPicks(1)
            } else if normalized < 0.25 {
                // Multiplier
                let mult_idx = (normalized * self.config.multiplier_values.len() as f64) as usize;
                let mult = self.config.multiplier_values
                    .get(mult_idx)
                    .copied()
                    .unwrap_or(2.0);
                PrizeType::Multiplier(mult)
            } else {
                // Coins
                let coin_idx = (normalized * self.config.base_coin_values.len() as f64) as usize;
                let base = self.config.base_coin_values
                    .get(coin_idx)
                    .copied()
                    .unwrap_or(10.0);
                PrizeType::Coins(base * bet)
            };

            items.push(PickItem {
                index: idx,
                prize,
                revealed: false,
            });
        }

        // Shuffle items (Fisher-Yates)
        for i in (1..items.len()).rev() {
            seed = (seed * 1103515245.0 + 12345.0) % 2147483648.0;
            let j = (seed as usize) % (i + 1);
            items.swap(i, j);
        }

        // Re-assign indices after shuffle
        for (i, item) in items.iter_mut().enumerate() {
            item.index = i as u8;
        }

        self.state.items = items;
    }

    /// Process a pick
    fn process_pick(&mut self, index: u8) -> bool {
        if let Some(item) = self.state.items.iter_mut().find(|i| i.index == index && !i.revealed) {
            item.revealed = true;
            self.state.picks_made += 1;
            self.state.last_pick_index = Some(index);

            match &item.prize {
                PrizeType::Coins(amount) => {
                    self.state.total_win += amount * self.state.multiplier;
                }
                PrizeType::Multiplier(mult) => {
                    self.state.multiplier *= mult;
                }
                PrizeType::ExtraPicks(extra) => {
                    self.state.extra_picks += extra;
                }
                PrizeType::Jackpot(tier) => {
                    self.state.jackpots_won.push(*tier);
                    // Jackpot value would be determined by engine
                    self.state.total_win += 1000.0 * (*tier as f64 + 1.0).powi(3);
                }
                PrizeType::EndGame | PrizeType::Collect => {
                    // Handled in game end logic
                }
            }

            true
        } else {
            false
        }
    }

    fn check_game_end(&self) -> bool {
        let end_games_hit = self.state.items.iter()
            .filter(|i| i.revealed && i.prize.is_end_game())
            .count() as u8;

        end_games_hit >= self.config.end_game_count
    }
}

impl Default for PickBonusChapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureChapter for PickBonusChapter {
    fn id(&self) -> FeatureId {
        FeatureId::new("pick_bonus")
    }

    fn name(&self) -> &str {
        "Pick Bonus"
    }

    fn category(&self) -> FeatureCategory {
        FeatureCategory::Bonus
    }

    fn description(&self) -> &str {
        "Pick hidden items to reveal prizes"
    }

    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError> {
        if let Some(total) = config.get::<u8>("total_items") {
            self.config.total_items = total.max(4).min(24);
        }
        if let Some(end_count) = config.get::<u8>("end_game_count") {
            self.config.end_game_count = end_count.max(1).min(5);
        }
        if let Some(jackpot_chance) = config.get::<f64>("jackpot_chance") {
            self.config.jackpot_chance = jackpot_chance.clamp(0.0, 0.1);
        }
        Ok(())
    }

    fn get_config(&self) -> FeatureConfig {
        let mut config = FeatureConfig::new();
        config.set("total_items", self.config.total_items);
        config.set("end_game_count", self.config.end_game_count);
        config.set("jackpot_chance", self.config.jackpot_chance);
        config
    }

    fn reset_config(&mut self) {
        self.config = PickBonusConfig::default();
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
            "picks_made".to_string(),
            serde_json::Value::from(self.state.picks_made),
        );
        data.insert(
            "extra_picks".to_string(),
            serde_json::Value::from(self.state.extra_picks),
        );
        data.insert(
            "multiplier".to_string(),
            serde_json::Value::from(self.state.multiplier),
        );
        data.insert(
            "total_items".to_string(),
            serde_json::Value::from(self.config.total_items),
        );
        data.insert(
            "items_revealed".to_string(),
            serde_json::Value::from(
                self.state.items.iter().filter(|i| i.revealed).count()
            ),
        );

        FeatureSnapshot {
            feature_id: "pick_bonus".to_string(),
            is_active: self.state.is_active,
            current_step: self.state.picks_made as u32,
            total_steps: Some(self.config.total_items as u32),
            multiplier: self.state.multiplier,
            accumulated_win: self.state.total_win,
            data,
        }
    }

    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
        self.state.is_active = snapshot.is_active;
        self.state.picks_made = snapshot.current_step as u8;
        self.state.multiplier = snapshot.multiplier;
        self.state.total_win = snapshot.accumulated_win;

        if let Some(extra) = snapshot.data.get("extra_picks").and_then(|v| v.as_u64()) {
            self.state.extra_picks = extra as u8;
        }
        Ok(())
    }

    fn can_activate(&self, context: &ActivationContext) -> bool {
        !self.state.is_active && context.bet > 0.0
    }

    fn activate(&mut self, context: &ActivationContext) {
        self.state = PickBonusState {
            is_active: true,
            items: Vec::new(),
            picks_made: 0,
            extra_picks: 0,
            total_win: 0.0,
            multiplier: 1.0,
            jackpots_won: Vec::new(),
            last_pick_index: None,
        };

        // Generate items using context for seeding
        let seed = context.bet * 12345.6789;
        self.generate_items(seed, context.bet);
    }

    fn deactivate(&mut self) {
        self.state.is_active = false;
    }

    fn reset(&mut self) {
        self.state = PickBonusState::default();
    }

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult {
        if !self.state.is_active {
            return FeatureResult::inactive();
        }

        // Use random value to select a pick (simulating player choice)
        let available: Vec<u8> = self.state.items.iter()
            .filter(|i| !i.revealed)
            .map(|i| i.index)
            .collect();

        if available.is_empty() {
            return FeatureResult::complete(self.state.total_win);
        }

        let pick_index = (context.random * available.len() as f64) as usize;
        let picked = available[pick_index];

        self.process_pick(picked);

        if self.check_game_end() {
            FeatureResult::complete(self.state.total_win)
        } else {
            FeatureResult::continue_with(self.state.total_win)
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

        // Pick step stage
        if let Some(last_idx) = self.state.last_pick_index {
            let pick_ts = timing.advance(800.0);

            if let Some(item) = self.state.items.iter().find(|i| i.index == last_idx) {
                let prize_desc = match &item.prize {
                    PrizeType::Coins(v) => format!("coins_{}", v),
                    PrizeType::Multiplier(m) => format!("mult_{}x", m),
                    PrizeType::ExtraPicks(n) => format!("extra_{}", n),
                    PrizeType::Jackpot(t) => format!("jackpot_{}", t),
                    PrizeType::EndGame => "end_game".to_string(),
                    PrizeType::Collect => "collect".to_string(),
                };

                stages.push(StageEvent::new(
                    Stage::FeatureStep {
                        step_index: self.state.picks_made as u32,
                        steps_remaining: Some(self.picks_remaining() as u32),
                        current_multiplier: self.state.multiplier,
                    },
                    pick_ts,
                ));

                // Prize reveal stage
                let reveal_ts = timing.advance(500.0);
                stages.push(StageEvent::new(
                    Stage::BonusPrizeReveal {
                        prize_type: prize_desc,
                        prize_value: match &item.prize {
                            PrizeType::Coins(v) => *v,
                            PrizeType::Multiplier(m) => *m,
                            PrizeType::ExtraPicks(n) => *n as f64,
                            PrizeType::Jackpot(t) => 1000.0 * (*t as f64 + 1.0).powi(3),
                            _ => 0.0,
                        },
                    },
                    reveal_ts,
                ));
            }
        }

        stages
    }

    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.feature_enter();
        vec![
            StageEvent::new(
                Stage::FeatureEnter {
                    feature_type: rf_stage::FeatureType::PickBonus,
                    total_steps: Some(self.config.total_items as u32),
                    multiplier: 1.0,
                },
                timestamp,
            ),
            StageEvent::new(
                Stage::BonusStart {
                    bonus_type: "pick".to_string(),
                    total_picks: self.config.total_items as u32,
                },
                timestamp + 100.0,
            ),
        ]
    }

    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let timestamp = timing.advance(1000.0);
        vec![
            StageEvent::new(
                Stage::BonusComplete {
                    total_win: self.state.total_win,
                    picks_used: self.state.picks_made as u32,
                },
                timestamp,
            ),
            StageEvent::new(
                Stage::FeatureExit {
                    total_win: self.state.total_win,
                },
                timestamp + 200.0,
            ),
        ]
    }

    fn stage_types(&self) -> Vec<&'static str> {
        vec![
            "FEATURE_ENTER",
            "BONUS_START",
            "FEATURE_STEP",
            "BONUS_PRIZE_REVEAL",
            "BONUS_COMPLETE",
            "FEATURE_EXIT",
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
    fn test_pick_bonus_creation() {
        let chapter = PickBonusChapter::new();
        assert_eq!(chapter.id().as_str(), "pick_bonus");
        assert_eq!(chapter.category(), FeatureCategory::Bonus);
    }

    #[test]
    fn test_pick_bonus_activation() {
        let mut chapter = PickBonusChapter::new();
        let context = ActivationContext::new(3, 1.0);

        assert!(chapter.can_activate(&context));
        chapter.activate(&context);
        assert!(chapter.is_active());
        assert_eq!(chapter.state.items.len(), 12); // Default total_items
    }

    #[test]
    fn test_pick_bonus_items_generation() {
        let mut chapter = PickBonusChapter::new();
        let context = ActivationContext::new(3, 1.0);

        chapter.activate(&context);

        // Should have exactly end_game_count end games
        let end_games = chapter.state.items.iter()
            .filter(|i| matches!(i.prize, PrizeType::EndGame))
            .count();
        assert_eq!(end_games, chapter.config.end_game_count as usize);

        // Should have one collect
        let collects = chapter.state.items.iter()
            .filter(|i| matches!(i.prize, PrizeType::Collect))
            .count();
        assert_eq!(collects, 1);
    }
}
