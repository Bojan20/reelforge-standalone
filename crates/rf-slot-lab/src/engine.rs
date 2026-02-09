//! Synthetic Slot Engine — Core simulation logic

use rand::prelude::*;
use serde::{Deserialize, Serialize};

use rf_stage::{BigWinTier, FeatureType, JackpotTier, StageEvent};

use crate::config::{FeatureConfig, SlotConfig, VolatilityProfile};
use crate::paytable::PayTable;
use crate::spin::{
    AnticipationInfo, AnticipationReason, CascadeResult, ForcedOutcome, JackpotWin, SpinResult,
    TriggeredFeature,
};
use crate::symbols::{ReelStrip, StandardSymbolSet, generate_balanced_strips};
use crate::timing::{TimestampGenerator, TimingConfig, TimingProfile};

/// Synthetic Slot Engine
///
/// Generates realistic slot game outcomes with configurable volatility,
/// features, and timing. Designed for audio-first development.
pub struct SyntheticSlotEngine {
    /// Configuration
    config: SlotConfig,
    /// Paytable
    paytable: PayTable,
    /// Reel strips
    reel_strips: Vec<ReelStrip>,
    /// Random number generator
    rng: StdRng,
    /// Timing configuration
    timing_config: TimingConfig,
    /// Timestamp generator
    timestamp_gen: TimestampGenerator,
    /// Current spin count
    spin_count: u64,
    /// Current session stats
    stats: SessionStats,
    /// Free spin state
    free_spin_state: Option<FreeSpinState>,
    /// Cascade state (prepared for advanced cascade tracking)
    #[allow(dead_code)]
    cascade_state: Option<CascadeState>,
    /// Current bet
    current_bet: f64,
    /// Jackpot pools
    jackpot_pools: [f64; 4],
}

/// Session statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SessionStats {
    pub total_spins: u64,
    pub total_bet: f64,
    pub total_win: f64,
    pub wins: u64,
    pub losses: u64,
    pub big_wins: u64,
    pub mega_wins: u64,
    pub features_triggered: u64,
    pub jackpots_won: u64,
    pub max_win_ratio: f64,
    pub cascade_chains: u64,
}

impl SessionStats {
    /// Calculate RTP
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

/// Free spin state (fields prepared for full free spin feature)
#[allow(dead_code)]
#[derive(Debug, Clone)]
struct FreeSpinState {
    remaining: u32,
    total: u32,
    total_win: f64,
    multiplier: f64,
    feature_type: FeatureType,
}

/// Cascade state (fields prepared for advanced cascade tracking)
#[allow(dead_code)]
#[derive(Debug, Clone)]
struct CascadeState {
    step: u32,
    total_win: f64,
    multiplier: f64,
    grids: Vec<Vec<Vec<u32>>>,
}

impl SyntheticSlotEngine {
    /// Create a new engine with default config
    pub fn new() -> Self {
        Self::with_config(SlotConfig::default())
    }

    /// Create with specific config
    pub fn with_config(config: SlotConfig) -> Self {
        let symbols = StandardSymbolSet::new();
        let reel_strips = generate_balanced_strips(&symbols, config.grid.reels, 100);
        let paytable = PayTable::standard(config.grid);
        let timing_config = TimingConfig::normal();

        Self {
            rng: StdRng::from_entropy(),
            timestamp_gen: TimestampGenerator::new(timing_config.clone()),
            config,
            paytable,
            reel_strips,
            timing_config,
            spin_count: 0,
            stats: SessionStats::default(),
            free_spin_state: None,
            cascade_state: None,
            current_bet: 1.0,
            jackpot_pools: [50.0, 200.0, 1000.0, 10000.0],
        }
    }

    /// Create for audio testing (high frequency events)
    pub fn audio_test() -> Self {
        Self::with_config(SlotConfig::audio_test())
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set volatility profile
    pub fn set_volatility(&mut self, volatility: VolatilityProfile) {
        self.config.volatility = volatility;
    }

    /// Set volatility by slider (0.0 = low, 1.0 = high)
    pub fn set_volatility_slider(&mut self, value: f64) {
        self.config.volatility = VolatilityProfile::interpolate(
            &VolatilityProfile::low(),
            &VolatilityProfile::high(),
            value,
        );
    }

    /// Set timing profile
    pub fn set_timing(&mut self, profile: TimingProfile) {
        self.timing_config = TimingConfig::from_profile(profile);
        self.timestamp_gen = TimestampGenerator::new(self.timing_config.clone());
    }

    /// Set bet amount
    pub fn set_bet(&mut self, bet: f64) {
        self.current_bet = bet.max(0.01);
    }

    /// Enable/disable features
    pub fn set_features(&mut self, features: FeatureConfig) {
        self.config.features = features;
    }

    /// Get current config
    pub fn config(&self) -> &SlotConfig {
        &self.config
    }

    /// Get current timing config
    pub fn timing_config(&self) -> &TimingConfig {
        &self.timing_config
    }

    /// Get session stats
    pub fn stats(&self) -> &SessionStats {
        &self.stats
    }

    /// Reset session stats
    pub fn reset_stats(&mut self) {
        self.stats = SessionStats::default();
        self.spin_count = 0;
    }

    /// Seed RNG for reproducible results
    pub fn seed(&mut self, seed: u64) {
        self.rng = StdRng::seed_from_u64(seed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Execute a random spin
    pub fn spin(&mut self) -> SpinResult {
        self.spin_internal(None, None)
    }

    /// Execute a spin with forced outcome
    pub fn spin_forced(&mut self, outcome: ForcedOutcome) -> SpinResult {
        self.spin_internal(Some(outcome), None)
    }

    /// Execute a spin with forced outcome AND specific target win multiplier
    ///
    /// This ensures the exact win tier by overriding the paytable-evaluated win amount
    /// with `bet * target_multiplier`. Use for precise tier testing (WIN_1, WIN_2, etc.)
    pub fn spin_forced_with_multiplier(
        &mut self,
        outcome: ForcedOutcome,
        target_multiplier: f64,
    ) -> SpinResult {
        self.spin_internal(Some(outcome), Some(target_multiplier))
    }

    fn spin_internal(
        &mut self,
        forced: Option<ForcedOutcome>,
        target_multiplier: Option<f64>,
    ) -> SpinResult {
        self.spin_count += 1;
        self.timestamp_gen.reset();

        let bet = self.current_bet;
        let spin_id = format!("spin-{:06}", self.spin_count);

        // Check if in free spins
        let (is_free_spin, free_spin_index, multiplier) =
            if let Some(ref mut fs) = self.free_spin_state {
                fs.remaining = fs.remaining.saturating_sub(1);
                (true, Some(fs.total - fs.remaining), fs.multiplier)
            } else {
                (false, None, 1.0)
            };

        // Generate grid
        let grid = if let Some(outcome) = forced {
            self.generate_forced_grid(outcome)
        } else {
            self.generate_random_grid()
        };

        // Evaluate wins
        let eval = self.paytable.evaluate(&grid, bet);
        let mut result = SpinResult::new(spin_id, grid.clone(), bet)
            .with_evaluation(eval)
            .with_big_win_tier(&self.config.volatility.win_tier_thresholds);

        result.is_free_spin = is_free_spin;
        result.free_spin_index = free_spin_index;
        result.multiplier = multiplier;
        result.total_win *= multiplier;

        // CRITICAL: Override win amount with target multiplier if specified
        // This ensures precise tier targeting (WIN_1, WIN_2, etc.)
        if let Some(target_mult) = target_multiplier {
            if target_mult > 0.0 {
                result.total_win = bet * target_mult;
                result.win_ratio = target_mult;
                // Recalculate big win tier with new amount
                result = result.with_big_win_tier(&self.config.volatility.win_tier_thresholds);
            }
        }

        // Check for special outcomes based on forced or random
        if let Some(outcome) = forced {
            self.apply_forced_outcome(&mut result, outcome);
        } else {
            self.apply_random_outcomes(&mut result);
        }

        // Handle cascades
        if self.config.features.cascades_enabled && result.is_win() {
            self.process_cascades(&mut result);
        }

        // Update stats
        self.update_stats(&result);

        // Update free spin state
        if let Some(ref mut fs) = self.free_spin_state {
            fs.total_win += result.total_win;
            if fs.remaining == 0 {
                // Feature ended
                self.free_spin_state = None;
            }
        }

        // Trigger new feature if applicable
        if result.feature_triggered.is_some() && self.free_spin_state.is_none() {
            if let Some(ref feature) = result.feature_triggered {
                self.free_spin_state = Some(FreeSpinState {
                    remaining: feature.total_spins,
                    total: feature.total_spins,
                    total_win: 0.0,
                    multiplier: feature.multiplier,
                    feature_type: feature.feature_type,
                });
            }
        }

        // Contribute to jackpots
        self.contribute_to_jackpots(bet);

        result
    }

    fn generate_random_grid(&mut self) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let mut grid = Vec::with_capacity(reels);

        for reel_idx in 0..reels {
            let strip = &self.reel_strips[reel_idx % self.reel_strips.len()];
            let start_pos = self.rng.gen_range(0..strip.len());

            let mut column = Vec::with_capacity(rows);
            for row in 0..rows {
                column.push(strip.symbol_at(start_pos + row));
            }
            grid.push(column);
        }

        grid
    }

    fn generate_forced_grid(&mut self, outcome: ForcedOutcome) -> Vec<Vec<u32>> {
        // Note: reels, rows, symbols available via self.config/paytable if needed
        match outcome {
            ForcedOutcome::Lose => self.generate_losing_grid(),
            ForcedOutcome::SmallWin => self.generate_win_grid(3, 0), // 3 of kind, tier 0
            ForcedOutcome::MediumWin => self.generate_win_grid(4, 0),
            ForcedOutcome::BigWin => self.generate_win_grid(5, 0),
            ForcedOutcome::MegaWin => self.generate_win_grid(5, 0), // Same but will be multiplied
            ForcedOutcome::EpicWin => self.generate_wild_win_grid(5),
            ForcedOutcome::UltraWin => self.generate_wild_win_grid(5),
            ForcedOutcome::FreeSpins => self.generate_scatter_grid(3),
            ForcedOutcome::NearMiss => self.generate_near_miss_grid(),
            ForcedOutcome::JackpotMini
            | ForcedOutcome::JackpotMinor
            | ForcedOutcome::JackpotMajor
            | ForcedOutcome::JackpotGrand => self.generate_random_grid(), // Jackpot is added separately
            ForcedOutcome::Cascade => self.generate_win_grid(3, 0),
        }
    }

    fn generate_losing_grid(&mut self) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let regular_ids = self.paytable.symbols.regular_ids();

        let mut grid = Vec::with_capacity(reels);
        for reel in 0..reels {
            let mut column = Vec::with_capacity(rows);
            for row in 0..rows {
                // Pick different symbols to avoid accidental wins
                let idx = (reel * 3 + row + 1) % regular_ids.len();
                column.push(regular_ids[idx]);
            }
            grid.push(column);
        }
        grid
    }

    fn generate_win_grid(&mut self, match_count: u8, tier: u8) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let regular_ids = self.paytable.symbols.regular_ids();

        // Pick a symbol for the win
        let winning_symbol = regular_ids
            .iter()
            .find(|&&id| {
                self.paytable
                    .symbols
                    .get(id)
                    .is_some_and(|s| s.tier == tier)
            })
            .copied()
            .unwrap_or(regular_ids[0]);

        let mut grid = Vec::with_capacity(reels);
        for reel in 0..reels {
            let mut column = vec![0u32; rows];
            // Put winning symbol on middle row for first N reels
            if reel < match_count as usize {
                column[1] = winning_symbol;
            } else {
                // Fill with random non-matching symbols
                for row in 0..rows {
                    let idx = self.rng.gen_range(0..regular_ids.len());
                    column[row] = regular_ids[idx];
                }
            }
            // Fill other rows
            for row in 0..rows {
                if column[row] == 0 {
                    let idx = self.rng.gen_range(0..regular_ids.len());
                    column[row] = regular_ids[idx];
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_wild_win_grid(&mut self, match_count: u8) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let regular_ids = self.paytable.symbols.regular_ids();
        let wild_id = self.paytable.wild_id;

        let winning_symbol = regular_ids[0]; // Highest paying

        let mut grid = Vec::with_capacity(reels);
        for reel in 0..reels {
            let mut column = vec![0u32; rows];
            if reel < match_count as usize {
                // Alternate between wild and symbol
                column[1] = if reel % 2 == 0 {
                    winning_symbol
                } else {
                    wild_id
                };
            }
            // Fill other positions
            for row in 0..rows {
                if column[row] == 0 {
                    let idx = self.rng.gen_range(0..regular_ids.len());
                    column[row] = regular_ids[idx];
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_scatter_grid(&mut self, scatter_count: u8) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let regular_ids = self.paytable.symbols.regular_ids();
        let scatter_id = self.paytable.scatter_id;

        let mut grid = Vec::with_capacity(reels);
        let mut scatters_placed = 0u8;

        for _reel in 0..reels {
            let mut column = vec![0u32; rows];
            // Place scatter on random row in first N reels
            if scatters_placed < scatter_count {
                let row = self.rng.gen_range(0..rows);
                column[row] = scatter_id;
                scatters_placed += 1;
            }
            // Fill other positions
            for row in 0..rows {
                if column[row] == 0 {
                    let idx = self.rng.gen_range(0..regular_ids.len());
                    column[row] = regular_ids[idx];
                }
            }
            grid.push(column);
        }
        grid
    }

    fn generate_near_miss_grid(&mut self) -> Vec<Vec<u32>> {
        let reels = self.config.grid.reels as usize;
        let rows = self.config.grid.rows as usize;
        let regular_ids = self.paytable.symbols.regular_ids();

        let winning_symbol = regular_ids[0];

        let mut grid = Vec::with_capacity(reels);
        for reel in 0..reels {
            let mut column = vec![0u32; rows];
            // Near miss: 2 matching, then just off
            if reel < 2 {
                column[1] = winning_symbol;
            } else if reel == 2 {
                // Put winning symbol just above or below the line
                column[0] = winning_symbol;
                column[1] = regular_ids[1];
            }
            // Fill other positions
            for row in 0..rows {
                if column[row] == 0 {
                    let idx = self.rng.gen_range(0..regular_ids.len());
                    column[row] = regular_ids[idx];
                }
            }
            grid.push(column);
        }
        grid
    }

    fn apply_forced_outcome(&mut self, result: &mut SpinResult, outcome: ForcedOutcome) {
        // Apply jackpot
        if let Some(tier) = outcome.jackpot_tier() {
            let tier_idx = match tier {
                JackpotTier::Mini => 0,
                JackpotTier::Minor => 1,
                JackpotTier::Major => 2,
                JackpotTier::Grand => 3,
                JackpotTier::Custom(_) => 0,
            };
            let amount = self.jackpot_pools[tier_idx];
            result.jackpot_won = Some(JackpotWin { tier, amount });
            result.total_win += amount;
            self.jackpot_pools[tier_idx] = self.config.features.jackpot_seeds[tier_idx];
        }

        // Apply feature trigger
        if outcome.triggers_feature() && result.scatter_win.is_some() {
            let spins = self.rng.gen_range(
                self.config.features.free_spins_range.0..=self.config.features.free_spins_range.1,
            );
            result.feature_triggered = Some(TriggeredFeature {
                feature_type: FeatureType::FreeSpins,
                total_spins: spins,
                multiplier: self.config.features.free_spins_multiplier,
            });
        }

        // Apply near miss flag (2026-02-01: Respects anticipation config)
        if matches!(outcome, ForcedOutcome::NearMiss) {
            result.near_miss = true;
            // Only set anticipation if enabled in config
            if self.config.anticipation.enable_near_miss_anticipation {
                // Near miss typically affects last 3 reels
                result.anticipation = Some(AnticipationInfo::from_reels(
                    vec![2, 3, 4],
                    AnticipationReason::NearMiss,
                    self.config.grid.reels,
                    self.timing_config.anticipation_duration_ms as u32,
                ));
            }
        }
    }

    fn apply_random_outcomes(&mut self, result: &mut SpinResult) {
        let vol = &self.config.volatility;

        // Check for feature trigger from scatter
        if result
            .scatter_win
            .as_ref()
            .is_some_and(|s| s.triggers_feature)
            && self.config.features.free_spins_enabled
        {
            let spins = self.rng.gen_range(
                self.config.features.free_spins_range.0..=self.config.features.free_spins_range.1,
            );
            result.feature_triggered = Some(TriggeredFeature {
                feature_type: FeatureType::FreeSpins,
                total_spins: spins,
                multiplier: self.config.features.free_spins_multiplier,
            });
        }

        // Random jackpot check
        if self.config.features.jackpot_enabled {
            let jackpot_roll: f64 = self.rng.r#gen::<f64>();
            if jackpot_roll < vol.jackpot_frequency {
                // Determine tier (weighted toward lower tiers)
                let tier_roll: f64 = self.rng.r#gen::<f64>();
                let (tier, tier_idx) = if tier_roll < 0.6 {
                    (JackpotTier::Mini, 0)
                } else if tier_roll < 0.85 {
                    (JackpotTier::Minor, 1)
                } else if tier_roll < 0.97 {
                    (JackpotTier::Major, 2)
                } else {
                    (JackpotTier::Grand, 3)
                };

                let amount = self.jackpot_pools[tier_idx];
                result.jackpot_won = Some(JackpotWin { tier, amount });
                result.total_win += amount;
                self.jackpot_pools[tier_idx] = self.config.features.jackpot_seeds[tier_idx];
            }
        }

        // Near miss detection (2026-02-01: Respects anticipation config)
        if !result.is_win() {
            let near_miss_roll: f64 = self.rng.r#gen::<f64>();
            if near_miss_roll < vol.near_miss_frequency {
                result.near_miss = true;
                // Only set anticipation if enabled in config
                if self.config.anticipation.enable_near_miss_anticipation {
                    result.anticipation = Some(AnticipationInfo::from_reels(
                        vec![3, 4],
                        AnticipationReason::NearMiss,
                        self.config.grid.reels,
                        self.timing_config.anticipation_duration_ms as u32,
                    ));
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // P7.1.5: Industry-Standard Anticipation System (V2)
        //
        // Uses AnticipationConfig from SlotConfig to determine:
        // - Which symbols trigger anticipation (Scatter, Bonus — NEVER Wild!)
        // - Which reels are allowed for triggers (Tip A: all, Tip B: 0,2,4)
        // - How many triggers needed (min_trigger_count)
        // - Sequential vs parallel reel stop during anticipation
        //
        // IMPORTANT: Wild symbols NEVER trigger anticipation per user requirement:
        // "Wild symbols should NEVER trigger anticipation"
        // ═══════════════════════════════════════════════════════════════════════════

        // Get anticipation config from SlotConfig
        let antic_config = &self.config.anticipation;

        // First, try scatter positions
        if let Some(ref scatter) = result.scatter_win {
            if scatter.count >= antic_config.min_trigger_count && !scatter.positions.is_empty() {
                // Check if scatter_id is a trigger symbol
                if antic_config.is_trigger_symbol(self.paytable.scatter_id) {
                    result.anticipation = AnticipationInfo::from_trigger_positions_with_config(
                        scatter.positions.clone(),
                        antic_config,
                        self.config.grid.reels,
                        self.timing_config.anticipation_duration_ms as u32,
                        AnticipationReason::Scatter,
                    );
                }
            }
        }

        // Check for bonus symbols (if not already triggered by scatter)
        // NOTE: This would require bonus detection logic which isn't in current paytable
        // Placeholder for future bonus symbol anticipation

        // CRITICAL: Wild symbols are NEVER checked for anticipation trigger
        // Even if result has wild_positions, we don't use them for anticipation
        // This is per explicit user requirement: "Wild symbols should NEVER trigger anticipation"
    }

    fn process_cascades(&mut self, result: &mut SpinResult) {
        if !result.is_win() {
            return;
        }

        let max_cascades = self.config.features.max_cascade_steps;
        let cascade_prob = self.config.volatility.cascade_probability;
        let mult_step = self.config.features.cascade_multiplier_step;

        let mut step = 0u32;
        let mut total_cascade_win = 0.0;
        let mut current_mult = 1.0;

        while step < max_cascades {
            // Check if cascade continues
            let cascade_roll: f64 = self.rng.r#gen::<f64>();
            if cascade_roll >= cascade_prob {
                break;
            }

            step += 1;
            current_mult += mult_step;

            // Generate new symbols in winning positions
            // (simplified: just generate a new grid)
            let cascade_grid = self.generate_random_grid();
            let cascade_eval = self.paytable.evaluate(&cascade_grid, result.bet);

            if !cascade_eval.is_win() {
                break;
            }

            let cascade_win = cascade_eval.total_win * current_mult;
            total_cascade_win += cascade_win;

            result.cascades.push(CascadeResult {
                step_index: step,
                grid: cascade_grid,
                win: cascade_win,
                multiplier: current_mult,
            });
        }

        if !result.cascades.is_empty() {
            result.total_win += total_cascade_win;
            result.win_ratio = result.total_win / result.bet;
            self.stats.cascade_chains += 1;
        }
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

        if let Some(ref tier) = result.big_win_tier {
            match tier {
                BigWinTier::BigWin => self.stats.big_wins += 1,
                BigWinTier::MegaWin | BigWinTier::EpicWin | BigWinTier::UltraWin => {
                    self.stats.mega_wins += 1;
                }
                _ => {}
            }
        }

        if result.feature_triggered.is_some() {
            self.stats.features_triggered += 1;
        }

        if result.jackpot_won.is_some() {
            self.stats.jackpots_won += 1;
        }

        if result.win_ratio > self.stats.max_win_ratio {
            self.stats.max_win_ratio = result.win_ratio;
        }
    }

    fn contribute_to_jackpots(&mut self, bet: f64) {
        // Contribute 1% of bet to jackpots
        let contribution = bet * 0.01;
        for pool in &mut self.jackpot_pools {
            *pool += contribution * 0.25; // Split evenly
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAGE GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Generate stage events for a spin result
    pub fn generate_stages(&mut self, result: &SpinResult) -> Vec<StageEvent> {
        self.timestamp_gen.reset();
        result.generate_stages(&mut self.timestamp_gen)
    }

    /// Execute spin and immediately generate stages
    pub fn spin_with_stages(&mut self) -> (SpinResult, Vec<StageEvent>) {
        let result = self.spin();
        let stages = self.generate_stages(&result);
        (result, stages)
    }

    /// Execute forced spin and immediately generate stages
    pub fn spin_forced_with_stages(
        &mut self,
        outcome: ForcedOutcome,
    ) -> (SpinResult, Vec<StageEvent>) {
        let result = self.spin_forced(outcome);
        let stages = self.generate_stages(&result);
        (result, stages)
    }

    /// Execute forced spin with target multiplier and immediately generate stages
    ///
    /// Use for precise tier testing: ensures win amount = bet * target_multiplier
    pub fn spin_forced_with_multiplier_and_stages(
        &mut self,
        outcome: ForcedOutcome,
        target_multiplier: f64,
    ) -> (SpinResult, Vec<StageEvent>) {
        let result = self.spin_forced_with_multiplier(outcome, target_multiplier);
        let stages = self.generate_stages(&result);
        (result, stages)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FREE SPIN STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// Check if currently in free spins
    pub fn in_free_spins(&self) -> bool {
        self.free_spin_state.is_some()
    }

    /// Get remaining free spins
    pub fn free_spins_remaining(&self) -> u32 {
        self.free_spin_state
            .as_ref()
            .map(|fs| fs.remaining)
            .unwrap_or(0)
    }

    /// Get free spin total win so far
    pub fn free_spins_total_win(&self) -> f64 {
        self.free_spin_state
            .as_ref()
            .map(|fs| fs.total_win)
            .unwrap_or(0.0)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SERIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Export config as JSON
    pub fn export_config(&self) -> String {
        serde_json::to_string_pretty(&self.config).unwrap_or_default()
    }

    /// Import config from JSON
    pub fn import_config(&mut self, json: &str) -> Result<(), String> {
        let config: SlotConfig =
            serde_json::from_str(json).map_err(|e| format!("Invalid config: {}", e))?;
        self.config = config;
        Ok(())
    }
}

impl Default for SyntheticSlotEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rf_stage::Stage;

    #[test]
    fn test_engine_creation() {
        let engine = SyntheticSlotEngine::new();
        assert_eq!(engine.stats().total_spins, 0);
    }

    #[test]
    fn test_basic_spin() {
        let mut engine = SyntheticSlotEngine::new();
        engine.seed(12345);

        let result = engine.spin();
        assert!(!result.grid.is_empty());
        assert_eq!(result.bet, 1.0);
    }

    #[test]
    fn test_forced_win() {
        let mut engine = SyntheticSlotEngine::new();

        let result = engine.spin_forced(ForcedOutcome::BigWin);
        assert!(result.is_win());
    }

    #[test]
    fn test_forced_loss() {
        let mut engine = SyntheticSlotEngine::new();

        let result = engine.spin_forced(ForcedOutcome::Lose);
        assert!(!result.is_win());
    }

    #[test]
    fn test_stage_generation() {
        let mut engine = SyntheticSlotEngine::audio_test();
        engine.seed(54321);

        let (result, stages) = engine.spin_with_stages();
        assert!(!stages.is_empty());

        // Should have spin_start at beginning
        assert!(matches!(stages.first().unwrap().stage, Stage::SpinStart));

        // Should have spin_end at end
        assert!(matches!(stages.last().unwrap().stage, Stage::SpinEnd));
    }

    #[test]
    fn test_free_spins_trigger() {
        let mut engine = SyntheticSlotEngine::new();

        let result = engine.spin_forced(ForcedOutcome::FreeSpins);
        assert!(result.feature_triggered.is_some());
        assert!(engine.in_free_spins());
    }

    #[test]
    fn test_session_stats() {
        let mut engine = SyntheticSlotEngine::new();
        engine.seed(11111);

        for _ in 0..100 {
            engine.spin();
        }

        let stats = engine.stats();
        assert_eq!(stats.total_spins, 100);
        assert!(stats.total_bet > 0.0);
    }

    #[test]
    fn test_volatility_slider() {
        let mut engine = SyntheticSlotEngine::new();

        engine.set_volatility_slider(0.0);
        assert!(engine.config().volatility.hit_rate > 0.30);

        engine.set_volatility_slider(1.0);
        assert!(engine.config().volatility.hit_rate < 0.25);
    }
}
