//! Engine V2 — GameModel-driven slot engine
//!
//! Integrates FeatureRegistry, GameModel, and mode switching.
//! This is the new API while maintaining backwards compatibility with engine.rs.

use rand::prelude::*;
use rf_stage::StageEvent;

use crate::features::{
    ActivationContext, CascadesChapter, FeatureCategory, FeatureChapter, FeatureRegistry,
    FreeSpinsChapter, GambleChapter, HoldAndWinChapter, JackpotChapter, SpinContext,
};
use crate::model::{GameMode, GameModel};
use crate::spin::{ForcedOutcome, SpinResult};
use crate::timing::TimestampGenerator;

/// Engine V2 — GameModel-driven slot engine
///
/// Uses the new GameModel and FeatureRegistry systems while
/// maintaining API compatibility with the original engine.
pub struct SlotEngineV2 {
    /// Game model
    model: GameModel,
    /// Feature registry
    features: FeatureRegistry,
    /// Random number generator
    rng: StdRng,
    /// Timestamp generator
    timestamp_gen: TimestampGenerator,
    /// Spin count
    spin_count: u64,
    /// Current bet
    current_bet: f64,
    /// Session stats
    stats: EngineStats,
}

/// Engine statistics
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct EngineStats {
    pub total_spins: u64,
    pub total_bet: f64,
    pub total_win: f64,
    pub wins: u64,
    pub losses: u64,
    pub features_triggered: u64,
    pub max_win_ratio: f64,
}

impl EngineStats {
    /// Calculate current RTP
    pub fn rtp(&self) -> f64 {
        if self.total_bet > 0.0 {
            (self.total_win / self.total_bet) * 100.0
        } else {
            0.0
        }
    }

    /// Calculate hit rate
    pub fn hit_rate(&self) -> f64 {
        if self.total_spins > 0 {
            (self.wins as f64 / self.total_spins as f64) * 100.0
        } else {
            0.0
        }
    }
}

impl SlotEngineV2 {
    /// Create engine from GameModel
    pub fn from_model(model: GameModel) -> Self {
        let timing_config = model.timing.clone();
        let mut features = FeatureRegistry::new();

        // Register built-in features based on model
        for feature_ref in &model.features {
            if feature_ref.builtin {
                match feature_ref.id.as_str() {
                    "free_spins" | "freespins" => {
                        features.register(Box::new(FreeSpinsChapter::new()));
                    }
                    "cascades" | "cascade" | "tumble" | "avalanche" => {
                        features.register(Box::new(CascadesChapter::new()));
                    }
                    "hold_and_win" | "holdandwin" | "hold_and_spin" => {
                        features.register(Box::new(HoldAndWinChapter::new()));
                    }
                    "jackpot" | "jackpots" => {
                        features.register(Box::new(JackpotChapter::new()));
                    }
                    "gamble" | "risk" => {
                        features.register(Box::new(GambleChapter::new()));
                    }
                    _ => {}
                }
            }
        }

        Self {
            timestamp_gen: TimestampGenerator::new(timing_config),
            model,
            features,
            rng: StdRng::from_entropy(),
            spin_count: 0,
            current_bet: 1.0,
            stats: EngineStats::default(),
        }
    }

    /// Create with default 5x3 model
    pub fn new() -> Self {
        Self::from_model(GameModel::standard_5x3("Default Game", "default"))
    }

    /// Set RNG seed for reproducibility
    pub fn seed(&mut self, seed: u64) {
        self.rng = StdRng::seed_from_u64(seed);
    }

    /// Set bet amount
    pub fn set_bet(&mut self, bet: f64) {
        self.current_bet = bet.max(0.01);
    }

    /// Get current bet
    pub fn bet(&self) -> f64 {
        self.current_bet
    }

    /// Get game model
    pub fn model(&self) -> &GameModel {
        &self.model
    }

    /// Get feature registry
    pub fn features(&self) -> &FeatureRegistry {
        &self.features
    }

    /// Get mutable feature registry
    pub fn features_mut(&mut self) -> &mut FeatureRegistry {
        &mut self.features
    }

    /// Get session stats
    pub fn stats(&self) -> &EngineStats {
        &self.stats
    }

    /// Reset session stats
    pub fn reset_stats(&mut self) {
        self.stats = EngineStats::default();
        self.spin_count = 0;
    }

    /// Check if game mode is math-driven
    pub fn is_math_driven(&self) -> bool {
        self.model.is_math_driven()
    }

    /// Set game mode
    pub fn set_mode(&mut self, mode: GameMode) {
        self.model.mode = mode;
    }

    /// Get current game mode
    pub fn mode(&self) -> GameMode {
        self.model.mode
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Execute a spin
    pub fn spin(&mut self) -> SpinResult {
        self.spin_internal(None)
    }

    /// Execute a spin with forced outcome
    pub fn spin_forced(&mut self, outcome: ForcedOutcome) -> SpinResult {
        self.spin_internal(Some(outcome))
    }

    fn spin_internal(&mut self, forced: Option<ForcedOutcome>) -> SpinResult {
        self.spin_count += 1;
        self.timestamp_gen.reset();

        let bet = self.current_bet;
        let spin_id = format!("v2-spin-{:06}", self.spin_count);

        // Generate grid based on mode
        let grid = match self.model.mode {
            GameMode::GddOnly => self.generate_scripted_grid(forced),
            GameMode::MathDriven => self.generate_math_grid(forced),
        };

        // Create base result
        let mut result = SpinResult::new(spin_id, grid, bet);

        // Generate random value for feature processing
        let random_value: f64 = self.rng.r#gen();

        // Check for feature activation
        let scatter_count = self.count_scatters(&result.grid);
        let activation_ctx = ActivationContext::new(scatter_count, bet);

        // Process features using iter_mut
        for (_, feature) in self.features.iter_mut() {
            if feature.can_activate(&activation_ctx) {
                feature.activate(&activation_ctx);
                self.stats.features_triggered += 1;
            }

            if feature.is_active() {
                let mut spin_ctx = SpinContext::new(bet)
                    .with_grid(result.grid.clone())
                    .with_multiplier(result.multiplier)
                    .with_random(random_value);
                spin_ctx.accumulated_win = result.total_win;

                feature.pre_spin(&spin_ctx);
                let feature_result = feature.process_spin(&mut spin_ctx);
                feature.post_spin(&spin_ctx, &feature_result);

                // Apply feature result
                result.total_win += feature_result.win_amount;
                if feature_result.multiplier != 1.0 {
                    result.multiplier *= feature_result.multiplier;
                }
            }
        }

        // Calculate win ratio
        result.win_ratio = if bet > 0.0 {
            result.total_win / bet
        } else {
            0.0
        };

        // Determine win tier
        if let Some(tier_name) = self.model.win_tiers.get_tier_name(result.win_ratio) {
            result.win_tier_name = Some(tier_name.to_string());
        }

        // Update stats
        self.update_stats(&result);

        result
    }

    fn generate_scripted_grid(&mut self, forced: Option<ForcedOutcome>) -> Vec<Vec<u32>> {
        let reels = self.model.grid.reels as usize;
        let rows = self.model.grid.rows as usize;

        // For scripted mode, generate based on forced outcome
        if let Some(outcome) = forced {
            self.generate_forced_grid(outcome)
        } else {
            // Generate random grid
            self.generate_random_grid(reels, rows)
        }
    }

    fn generate_math_grid(&mut self, forced: Option<ForcedOutcome>) -> Vec<Vec<u32>> {
        if let Some(outcome) = forced {
            return self.generate_forced_grid(outcome);
        }

        let reels = self.model.grid.reels as usize;
        let rows = self.model.grid.rows as usize;

        // Use math model weights if available
        if self.model.math.is_some() {
            self.generate_weighted_grid(reels, rows)
        } else {
            self.generate_random_grid(reels, rows)
        }
    }

    fn generate_random_grid(&mut self, reels: usize, rows: usize) -> Vec<Vec<u32>> {
        let mut grid = Vec::with_capacity(reels);
        for _ in 0..reels {
            let mut column = Vec::with_capacity(rows);
            for _ in 0..rows {
                // Symbol IDs 1-10 (standard set)
                column.push(self.rng.gen_range(1..=10));
            }
            grid.push(column);
        }
        grid
    }

    fn generate_weighted_grid(&mut self, reels: usize, rows: usize) -> Vec<Vec<u32>> {
        let mut grid = Vec::with_capacity(reels);

        // Clone math model to avoid borrow issues
        let math = self.model.math.clone();

        for reel in 0..reels {
            let mut column = Vec::with_capacity(rows);

            if let Some(ref math) = math {
                let total_weight = math.symbol_weights.total_weight(reel);

                for _ in 0..rows {
                    if total_weight > 0 {
                        let roll = self.rng.gen_range(0..total_weight);
                        let symbol_id = Self::select_symbol_by_weight_static(math, reel, roll);
                        column.push(symbol_id);
                    } else {
                        column.push(self.rng.gen_range(1..=10));
                    }
                }
            } else {
                for _ in 0..rows {
                    column.push(self.rng.gen_range(1..=10));
                }
            }
            grid.push(column);
        }
        grid
    }

    fn select_symbol_by_weight_static(
        math: &crate::model::MathModel,
        reel: usize,
        roll: u32,
    ) -> u32 {
        let mut cumulative = 0u32;
        for (symbol_id, weights) in &math.symbol_weights.weights {
            if let Some(&weight) = weights.get(reel) {
                cumulative += weight;
                if roll < cumulative {
                    return *symbol_id;
                }
            }
        }
        1 // Default
    }

    fn generate_forced_grid(&mut self, outcome: ForcedOutcome) -> Vec<Vec<u32>> {
        let reels = self.model.grid.reels as usize;
        let rows = self.model.grid.rows as usize;

        match outcome {
            ForcedOutcome::Lose => self.generate_losing_grid(reels, rows),
            ForcedOutcome::SmallWin => self.generate_win_grid(reels, rows, 3),
            ForcedOutcome::MediumWin => self.generate_win_grid(reels, rows, 4),
            ForcedOutcome::BigWin => self.generate_win_grid(reels, rows, 5),
            ForcedOutcome::MegaWin => self.generate_big_win_grid(reels, rows),
            ForcedOutcome::EpicWin => self.generate_big_win_grid(reels, rows),
            ForcedOutcome::UltraWin => self.generate_big_win_grid(reels, rows),
            ForcedOutcome::FreeSpins => self.generate_scatter_grid(reels, rows, 3),
            ForcedOutcome::NearMiss => self.generate_near_miss_grid(reels, rows),
            _ => self.generate_random_grid(reels, rows),
        }
    }

    fn generate_losing_grid(&mut self, reels: usize, rows: usize) -> Vec<Vec<u32>> {
        let mut grid = Vec::with_capacity(reels);
        for reel in 0..reels {
            let mut column = Vec::with_capacity(rows);
            for row in 0..rows {
                // Alternate symbols to prevent accidental wins
                let symbol = ((reel * 3 + row) % 8 + 1) as u32;
                column.push(symbol);
            }
            grid.push(column);
        }
        grid
    }

    fn generate_win_grid(
        &mut self,
        reels: usize,
        rows: usize,
        match_count: usize,
    ) -> Vec<Vec<u32>> {
        let winning_symbol = self.rng.gen_range(1..=5) as u32;
        let mut grid = Vec::with_capacity(reels);

        for reel in 0..reels {
            let mut column = vec![0u32; rows];
            if reel < match_count {
                column[1] = winning_symbol; // Middle row
            }
            // Fill rest
            for row in 0..rows {
                if column[row] == 0 {
                    column[row] = self.rng.gen_range(6..=10);
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_big_win_grid(&mut self, reels: usize, rows: usize) -> Vec<Vec<u32>> {
        // Full line of high-paying symbol
        let winning_symbol = 1u32; // Highest paying
        let mut grid = Vec::with_capacity(reels);

        for _ in 0..reels {
            let mut column = Vec::with_capacity(rows);
            for row in 0..rows {
                if row == 1 {
                    column.push(winning_symbol);
                } else {
                    column.push(self.rng.gen_range(2..=10));
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_scatter_grid(
        &mut self,
        reels: usize,
        rows: usize,
        scatter_count: usize,
    ) -> Vec<Vec<u32>> {
        let scatter_id = 10u32; // Scatter symbol
        let mut grid = Vec::with_capacity(reels);
        let mut placed = 0;

        for _reel in 0..reels {
            let mut column = vec![0u32; rows];
            if placed < scatter_count {
                let row = self.rng.gen_range(0..rows);
                column[row] = scatter_id;
                placed += 1;
            }
            for row in 0..rows {
                if column[row] == 0 {
                    column[row] = self.rng.gen_range(1..=8);
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_near_miss_grid(&mut self, reels: usize, rows: usize) -> Vec<Vec<u32>> {
        let winning_symbol = 1u32;
        let mut grid = Vec::with_capacity(reels);

        for reel in 0..reels {
            let mut column = vec![0u32; rows];
            if reel < 2 {
                column[1] = winning_symbol;
            } else if reel == 2 {
                // Near miss: symbol just above
                column[0] = winning_symbol;
                column[1] = self.rng.gen_range(2..=10);
            }
            for row in 0..rows {
                if column[row] == 0 {
                    column[row] = self.rng.gen_range(2..=10);
                }
            }
            grid.push(column);
        }
        grid
    }

    fn count_scatters(&self, grid: &[Vec<u32>]) -> u8 {
        let scatter_id = 10u32;
        grid.iter()
            .flat_map(|col| col.iter())
            .filter(|&&s| s == scatter_id)
            .count() as u8
    }

    fn update_stats(&mut self, result: &SpinResult) {
        self.stats.total_spins += 1;
        self.stats.total_bet += result.bet;
        self.stats.total_win += result.total_win;

        if result.is_win() {
            self.stats.wins += 1;
        } else {
            self.stats.losses += 1;
        }

        if result.win_ratio > self.stats.max_win_ratio {
            self.stats.max_win_ratio = result.win_ratio;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAGE GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Generate stage events for a spin result
    pub fn generate_stages(&mut self, result: &SpinResult) -> Vec<StageEvent> {
        self.timestamp_gen.reset();
        let mut stages = result.generate_stages(&mut self.timestamp_gen);

        // Add feature stages
        for (_, feature) in self.features.iter() {
            if feature.is_active() {
                let feature_stages = feature.generate_stages(&mut self.timestamp_gen);
                stages.extend(feature_stages);
            }
        }

        // Sort by timestamp
        stages.sort_by(|a, b| {
            a.timestamp_ms
                .partial_cmp(&b.timestamp_ms)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        stages
    }

    /// Execute spin and generate stages in one call
    pub fn spin_with_stages(&mut self) -> (SpinResult, Vec<StageEvent>) {
        let result = self.spin();
        let stages = self.generate_stages(&result);
        (result, stages)
    }

    /// Execute forced spin and generate stages
    pub fn spin_forced_with_stages(
        &mut self,
        outcome: ForcedOutcome,
    ) -> (SpinResult, Vec<StageEvent>) {
        let result = self.spin_forced(outcome);
        let stages = self.generate_stages(&result);
        (result, stages)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEATURE QUERIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// Check if any feature is currently active
    pub fn any_feature_active(&self) -> bool {
        self.features.iter().any(|(_, f)| f.is_active())
    }

    /// Get active feature IDs
    pub fn active_feature_ids(&self) -> Vec<String> {
        self.features
            .iter()
            .filter(|(_, f)| f.is_active())
            .map(|(id, _)| id.to_string())
            .collect()
    }

    /// Get features by category
    pub fn features_by_category(&self, category: FeatureCategory) -> Vec<&dyn FeatureChapter> {
        self.features
            .list_by_category(category)
            .iter()
            .filter_map(|id| self.features.get(id))
            .collect()
    }
}

impl Default for SlotEngineV2 {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::FeatureId;

    #[test]
    fn test_engine_v2_creation() {
        let engine = SlotEngineV2::new();
        assert_eq!(engine.stats().total_spins, 0);
        assert_eq!(engine.model().grid.reels, 5);
        assert_eq!(engine.model().grid.rows, 3);
    }

    #[test]
    fn test_engine_v2_from_model() {
        let model = GameModel::standard_5x3("Test Game", "test");
        let engine = SlotEngineV2::from_model(model);
        assert_eq!(engine.model().info.name, "Test Game");
    }

    #[test]
    fn test_engine_v2_spin() {
        let mut engine = SlotEngineV2::new();
        engine.seed(12345);

        let result = engine.spin();
        assert!(!result.grid.is_empty());
        assert_eq!(result.bet, 1.0);
        assert_eq!(engine.stats().total_spins, 1);
    }

    #[test]
    fn test_engine_v2_forced_spin() {
        let mut engine = SlotEngineV2::new();

        let result = engine.spin_forced(ForcedOutcome::BigWin);
        assert!(!result.grid.is_empty());
    }

    #[test]
    fn test_engine_v2_stages() {
        let mut engine = SlotEngineV2::new();
        engine.seed(54321);

        let (result, stages) = engine.spin_with_stages();
        assert!(!result.grid.is_empty());
        assert!(!stages.is_empty());
    }

    #[test]
    fn test_engine_v2_feature_registry() {
        let model = GameModel::standard_5x3("Feature Test", "ftest");
        let engine = SlotEngineV2::from_model(model);

        // Should have free_spins and cascades registered
        assert!(engine.features().get(&FeatureId::new("free_spins")).is_some());
        assert!(engine.features().get(&FeatureId::new("cascades")).is_some());
    }

    #[test]
    fn test_engine_v2_math_driven() {
        let mut model = GameModel::standard_5x3("Math Test", "math");
        model.mode = GameMode::MathDriven;
        model.math = Some(crate::model::MathModel::standard());

        let engine = SlotEngineV2::from_model(model);
        assert!(engine.is_math_driven());
    }
}
