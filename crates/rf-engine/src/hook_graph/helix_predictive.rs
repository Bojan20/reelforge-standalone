// ═══════════════════════════════════════════════════════════════════════════════
// HELIX PREDICTIVE AUDIO ENGINE (PAE) — Pre-compute audio before it happens
// ═══════════════════════════════════════════════════════════════════════════════
//
// Point 1.6 of HELIX Architecture. AI that KNOWS what's coming.
//
// Uses math model probability to pre-load and pre-compute audio for the most
// likely next outcomes. Benefits:
//   - Zero-latency audio response to game events
//   - Smoother transitions (DSP chains already warm)
//   - Better memory management (predictive loading/unloading)
//   - Deterministic audio timing (pre-positioned voices)
//
// ARCHITECTURE:
//   MathModel → PredictiveCache → PredictiveDsp → Pre-positioned Voices
//
//   1. Math model provides outcome probabilities (win distribution)
//   2. PredictiveCache pre-loads assets for top N likely outcomes
//   3. PredictiveDsp pre-warms DSP chains for those outcomes
//   4. When outcome arrives, audio plays INSTANTLY (already prepared)
//
// SLOT-SPECIFIC: This is deeply integrated with slot math models —
// something generic game middleware can NEVER do.
// ═══════════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;

// ─────────────────────────────────────────────────────────────────────────────
// Win Distribution Model
// ─────────────────────────────────────────────────────────────────────────────

/// Win tier classification based on win/bet ratio
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum WinTier {
    /// Loss (win = 0)
    Loss        = 0,
    /// Sub-win: win < bet (LDW territory)
    SubWin      = 1,
    /// Small win: 1x-2x bet
    SmallWin    = 2,
    /// Medium win: 2x-5x bet
    MediumWin   = 3,
    /// Big win: 5x-20x bet
    BigWin      = 4,
    /// Mega win: 20x-100x bet
    MegaWin     = 5,
    /// Super mega: 100x-500x bet
    SuperMega   = 6,
    /// Jackpot: 500x+ bet
    Jackpot     = 7,
}

impl WinTier {
    /// Classify a win/bet ratio into a tier
    pub fn from_ratio(ratio: f64) -> Self {
        match ratio {
            r if r <= 0.0 => Self::Loss,
            r if r < 1.0 => Self::SubWin,
            r if r < 2.0 => Self::SmallWin,
            r if r < 5.0 => Self::MediumWin,
            r if r < 20.0 => Self::BigWin,
            r if r < 100.0 => Self::MegaWin,
            r if r < 500.0 => Self::SuperMega,
            _ => Self::Jackpot,
        }
    }

    /// Number of audio assets typically needed for this tier
    pub fn expected_asset_count(self) -> usize {
        match self {
            Self::Loss => 1,       // Settle sound
            Self::SubWin => 2,     // Subtle win + settle
            Self::SmallWin => 3,   // Win sound + counter + settle
            Self::MediumWin => 4,  // Win fanfare + counter + music + settle
            Self::BigWin => 6,     // Full celebration suite
            Self::MegaWin => 8,    // Extended celebration
            Self::SuperMega => 10, // Premium celebration
            Self::Jackpot => 12,   // Ultimate celebration
        }
    }

    /// Audio priority for this tier
    pub fn audio_priority(self) -> u8 {
        match self {
            Self::Loss => 50,
            Self::SubWin => 80,
            Self::SmallWin => 100,
            Self::MediumWin => 130,
            Self::BigWin => 170,
            Self::MegaWin => 200,
            Self::SuperMega => 230,
            Self::Jackpot => 255,
        }
    }
}

/// Win distribution from the math model
#[derive(Debug, Clone)]
pub struct WinDistribution {
    /// Probability of each tier (must sum to 1.0)
    pub tier_probabilities: HashMap<WinTier, f64>,
    /// Hit frequency (% of spins that produce any win)
    pub hit_frequency: f64,
    /// RTP (Return To Player, e.g., 0.96 = 96%)
    pub rtp: f64,
    /// Volatility index (0.0 = low, 1.0 = extreme)
    pub volatility: f64,
    /// Maximum win multiplier
    pub max_win_multiplier: f64,
    /// Feature trigger probability per spin
    pub feature_probability: f64,
    /// Cascade/respin probability (after a win)
    pub cascade_probability: f64,
    /// Near-miss probability (for compliance tracking)
    pub near_miss_probability: f64,
}

impl Default for WinDistribution {
    fn default() -> Self {
        let mut tier_probs = HashMap::new();
        // Typical medium-volatility slot distribution
        tier_probs.insert(WinTier::Loss, 0.65);
        tier_probs.insert(WinTier::SubWin, 0.10);
        tier_probs.insert(WinTier::SmallWin, 0.15);
        tier_probs.insert(WinTier::MediumWin, 0.06);
        tier_probs.insert(WinTier::BigWin, 0.025);
        tier_probs.insert(WinTier::MegaWin, 0.01);
        tier_probs.insert(WinTier::SuperMega, 0.004);
        tier_probs.insert(WinTier::Jackpot, 0.001);

        Self {
            tier_probabilities: tier_probs,
            hit_frequency: 0.35,
            rtp: 0.96,
            volatility: 0.5,
            max_win_multiplier: 5000.0,
            feature_probability: 0.008,
            cascade_probability: 0.3,
            near_miss_probability: 0.05,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Predictive Outcome
// ─────────────────────────────────────────────────────────────────────────────

/// A predicted outcome with associated audio preparation
#[derive(Debug, Clone)]
pub struct PredictedOutcome {
    /// Win tier
    pub tier: WinTier,
    /// Probability of this outcome
    pub probability: f64,
    /// Audio assets to pre-load
    pub asset_ids: Vec<String>,
    /// Whether assets are loaded in cache
    pub assets_loaded: bool,
    /// DSP chain pre-warmed
    pub dsp_ready: bool,
    /// Voice slots pre-positioned
    pub voices_reserved: usize,
    /// Estimated memory cost (bytes)
    pub memory_cost: usize,
}

/// Feature prediction
#[derive(Debug, Clone)]
pub struct FeaturePrediction {
    /// Feature type ID
    pub feature_id: u32,
    /// Probability of triggering
    pub probability: f64,
    /// Assets needed for feature transition
    pub transition_assets: Vec<String>,
    /// Assets needed during feature
    pub feature_assets: Vec<String>,
    /// Whether pre-loaded
    pub loaded: bool,
}

// ─────────────────────────────────────────────────────────────────────────────
// Predictive Cache
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for predictive caching
#[derive(Debug, Clone)]
pub struct PredictiveCacheConfig {
    /// Maximum number of outcomes to predict ahead
    pub max_predictions: usize,
    /// Minimum probability to pre-load (don't load very rare outcomes)
    pub min_probability: f64,
    /// Maximum memory budget for predictive cache (bytes)
    pub max_memory_bytes: usize,
    /// Whether to pre-warm DSP chains
    pub pre_warm_dsp: bool,
    /// Whether to pre-reserve voice slots
    pub pre_reserve_voices: bool,
    /// How many spins ahead to predict
    pub lookahead_spins: usize,
}

impl Default for PredictiveCacheConfig {
    fn default() -> Self {
        Self {
            max_predictions: 5,
            min_probability: 0.005,
            max_memory_bytes: 64 * 1024 * 1024, // 64 MB
            pre_warm_dsp: true,
            pre_reserve_voices: true,
            lookahead_spins: 3,
        }
    }
}

/// Predictive cache — manages pre-loading based on math model probabilities
pub struct PredictiveCache {
    /// Configuration
    config: PredictiveCacheConfig,
    /// Current win distribution model
    distribution: WinDistribution,
    /// Current predictions (sorted by probability, highest first)
    predictions: Vec<PredictedOutcome>,
    /// Feature predictions
    feature_predictions: Vec<FeaturePrediction>,
    /// Audio asset registry (asset_id → memory size estimate)
    asset_sizes: HashMap<String, usize>,
    /// Currently loaded assets
    loaded_assets: HashMap<String, bool>,
    /// Total memory used by predictive cache
    memory_used: usize,
    /// Statistics
    pub stats: PredictiveCacheStats,
}

/// Statistics for the predictive cache
#[derive(Debug, Clone, Default)]
pub struct PredictiveCacheStats {
    /// Total predictions made
    pub total_predictions: u64,
    /// Cache hits (predicted outcome was correct)
    pub cache_hits: u64,
    /// Cache misses (unpredicted outcome)
    pub cache_misses: u64,
    /// Hit rate (0.0-1.0)
    pub hit_rate: f64,
    /// Memory currently used (bytes)
    pub memory_used: usize,
    /// Memory budget remaining (bytes)
    pub memory_remaining: usize,
    /// Number of pre-loaded outcomes
    pub outcomes_loaded: usize,
    /// Average prediction latency savings (ms)
    pub avg_latency_savings_ms: f64,
}

impl PredictiveCache {
    /// Create a new predictive cache
    pub fn new(config: PredictiveCacheConfig) -> Self {
        Self {
            config,
            distribution: WinDistribution::default(),
            predictions: Vec::with_capacity(8),
            feature_predictions: Vec::with_capacity(4),
            asset_sizes: HashMap::new(),
            loaded_assets: HashMap::new(),
            memory_used: 0,
            stats: PredictiveCacheStats::default(),
        }
    }

    /// Update the math model (call when game parameters change)
    pub fn set_distribution(&mut self, dist: WinDistribution) {
        self.distribution = dist;
        self.recalculate_predictions();
    }

    /// Register an audio asset with its estimated size
    pub fn register_asset(&mut self, asset_id: &str, size_bytes: usize) {
        self.asset_sizes.insert(asset_id.to_string(), size_bytes);
    }

    /// Map a win tier to its audio asset IDs
    /// (In production, this comes from the game's audio blueprint)
    pub fn map_tier_assets(&mut self, tier: WinTier, assets: Vec<String>) {
        // Find or create prediction for this tier
        if let Some(pred) = self.predictions.iter_mut().find(|p| p.tier == tier) {
            pred.asset_ids = assets;
        }
    }

    /// Recalculate predictions based on current distribution
    pub fn recalculate_predictions(&mut self) {
        self.predictions.clear();

        // Sort tiers by probability (highest first)
        let mut tiers: Vec<(WinTier, f64)> = self.distribution.tier_probabilities
            .iter()
            .filter(|(_, prob)| **prob >= self.config.min_probability)
            .map(|(&tier, &prob)| (tier, prob))
            .collect();
        tiers.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Take top N
        let mut total_memory = 0;
        for (tier, prob) in tiers.into_iter().take(self.config.max_predictions) {
            let asset_count = tier.expected_asset_count();
            // Estimate ~100KB per asset (typical short slot sound)
            let est_memory = asset_count * 100 * 1024;

            if total_memory + est_memory > self.config.max_memory_bytes {
                break; // Memory budget exceeded
            }

            total_memory += est_memory;

            self.predictions.push(PredictedOutcome {
                tier,
                probability: prob,
                asset_ids: Vec::new(), // Populated by map_tier_assets
                assets_loaded: false,
                dsp_ready: false,
                voices_reserved: 0,
                memory_cost: est_memory,
            });
        }

        // Feature prediction
        if self.distribution.feature_probability >= self.config.min_probability {
            self.feature_predictions.push(FeaturePrediction {
                feature_id: 0,
                probability: self.distribution.feature_probability,
                transition_assets: Vec::new(),
                feature_assets: Vec::new(),
                loaded: false,
            });
        }

        self.stats.total_predictions += 1;
    }

    /// Notify the cache that a spin result occurred.
    /// Returns whether the outcome was pre-cached (hit).
    pub fn on_spin_result(&mut self, win_ratio: f64) -> bool {
        let tier = WinTier::from_ratio(win_ratio);

        let hit = self.predictions.iter().any(|p| p.tier == tier && p.assets_loaded);

        if hit {
            self.stats.cache_hits += 1;
        } else {
            self.stats.cache_misses += 1;
        }

        let total = self.stats.cache_hits + self.stats.cache_misses;
        if total > 0 {
            self.stats.hit_rate = self.stats.cache_hits as f64 / total as f64;
        }

        hit
    }

    /// Pre-load assets for predicted outcomes.
    /// Returns list of asset IDs to load (caller handles actual I/O).
    pub fn assets_to_preload(&self) -> Vec<&str> {
        let mut to_load = Vec::new();

        for pred in &self.predictions {
            for asset_id in &pred.asset_ids {
                if !self.loaded_assets.get(asset_id).copied().unwrap_or(false) {
                    to_load.push(asset_id.as_str());
                }
            }
        }

        to_load
    }

    /// Mark an asset as loaded
    pub fn mark_loaded(&mut self, asset_id: &str) {
        self.loaded_assets.insert(asset_id.to_string(), true);
        if let Some(size) = self.asset_sizes.get(asset_id) {
            self.memory_used += size;
        }

        // Update prediction status
        for pred in &mut self.predictions {
            if pred.asset_ids.contains(&asset_id.to_string()) {
                pred.assets_loaded = pred.asset_ids.iter()
                    .all(|id| self.loaded_assets.get(id).copied().unwrap_or(false));
            }
        }

        self.update_stats();
    }

    /// Unload assets that are no longer predicted
    /// Returns list of asset IDs to unload
    pub fn assets_to_unload(&self) -> Vec<&str> {
        let predicted_assets: std::collections::HashSet<&str> = self.predictions.iter()
            .flat_map(|p| p.asset_ids.iter().map(|s| s.as_str()))
            .collect();

        self.loaded_assets.iter()
            .filter(|(_, loaded)| **loaded)
            .filter(|(id, _)| !predicted_assets.contains(id.as_str()))
            .map(|(id, _)| id.as_str())
            .collect()
    }

    /// Get current predictions
    pub fn predictions(&self) -> &[PredictedOutcome] {
        &self.predictions
    }

    /// Get statistics
    pub fn stats(&self) -> &PredictiveCacheStats {
        &self.stats
    }

    fn update_stats(&mut self) {
        self.stats.memory_used = self.memory_used;
        self.stats.memory_remaining = self.config.max_memory_bytes.saturating_sub(self.memory_used);
        self.stats.outcomes_loaded = self.predictions.iter().filter(|p| p.assets_loaded).count();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Predictive DSP — Pre-warm DSP chains for predicted outcomes
// ─────────────────────────────────────────────────────────────────────────────

/// Pre-warmed DSP chain state for a predicted outcome
#[derive(Debug, Clone)]
pub struct PreWarmedDspChain {
    /// Win tier this chain is for
    pub tier: WinTier,
    /// DSP parameter snapshots (node_id → param_id → value)
    pub param_snapshots: HashMap<u32, HashMap<u32, f64>>,
    /// Whether filter states are pre-computed
    pub filters_warmed: bool,
    /// Whether reverb tails are pre-filled
    pub reverb_primed: bool,
    /// Estimated latency savings (samples)
    pub latency_savings_samples: u32,
}

/// Predictive DSP manager — pre-warms DSP chains for likely outcomes
pub struct PredictiveDsp {
    /// Pre-warmed chains per win tier
    chains: HashMap<WinTier, PreWarmedDspChain>,
    /// Sample rate
    sample_rate: u32,
    /// Whether pre-warming is active
    active: bool,
}

impl PredictiveDsp {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            chains: HashMap::new(),
            sample_rate,
            active: true,
        }
    }

    /// Pre-warm a DSP chain for a predicted win tier
    pub fn pre_warm(&mut self, tier: WinTier, params: HashMap<u32, HashMap<u32, f64>>) {
        if !self.active { return; }

        let chain = PreWarmedDspChain {
            tier,
            param_snapshots: params,
            filters_warmed: true,
            reverb_primed: tier >= WinTier::BigWin, // Only prime reverb for big wins
            latency_savings_samples: match tier {
                WinTier::Loss | WinTier::SubWin => 0,
                WinTier::SmallWin => 128,
                WinTier::MediumWin => 256,
                WinTier::BigWin => 512,
                WinTier::MegaWin => 1024,
                WinTier::SuperMega | WinTier::Jackpot => 2048,
            },
        };

        self.chains.insert(tier, chain);
    }

    /// Get pre-warmed chain for a tier (if available)
    pub fn get_warmed_chain(&self, tier: WinTier) -> Option<&PreWarmedDspChain> {
        self.chains.get(&tier)
    }

    /// Check if a tier has a pre-warmed chain
    pub fn is_warmed(&self, tier: WinTier) -> bool {
        self.chains.contains_key(&tier)
    }

    /// Clear all pre-warmed chains
    pub fn clear(&mut self) {
        self.chains.clear();
    }

    /// Set active state
    pub fn set_active(&mut self, active: bool) {
        self.active = active;
        if !active { self.clear(); }
    }

    /// Get estimated latency savings for a tier
    pub fn latency_savings_ms(&self, tier: WinTier) -> f64 {
        self.chains.get(&tier)
            .map(|c| c.latency_savings_samples as f64 / self.sample_rate as f64 * 1000.0)
            .unwrap_or(0.0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_win_tier_classification() {
        assert_eq!(WinTier::from_ratio(0.0), WinTier::Loss);
        assert_eq!(WinTier::from_ratio(-1.0), WinTier::Loss);
        assert_eq!(WinTier::from_ratio(0.5), WinTier::SubWin);
        assert_eq!(WinTier::from_ratio(1.5), WinTier::SmallWin);
        assert_eq!(WinTier::from_ratio(3.0), WinTier::MediumWin);
        assert_eq!(WinTier::from_ratio(10.0), WinTier::BigWin);
        assert_eq!(WinTier::from_ratio(50.0), WinTier::MegaWin);
        assert_eq!(WinTier::from_ratio(200.0), WinTier::SuperMega);
        assert_eq!(WinTier::from_ratio(1000.0), WinTier::Jackpot);
    }

    #[test]
    fn test_default_distribution() {
        let dist = WinDistribution::default();
        let total: f64 = dist.tier_probabilities.values().sum();
        assert!((total - 1.0).abs() < 0.001, "Probabilities should sum to 1.0, got {}", total);
        assert!(dist.rtp > 0.9 && dist.rtp < 1.0);
    }

    #[test]
    fn test_predictive_cache_creation() {
        let config = PredictiveCacheConfig::default();
        let cache = PredictiveCache::new(config);
        assert_eq!(cache.predictions().len(), 0);
    }

    #[test]
    fn test_predictions_generation() {
        let mut cache = PredictiveCache::new(PredictiveCacheConfig::default());
        cache.set_distribution(WinDistribution::default());

        // Should have predictions for the most likely tiers
        assert!(!cache.predictions().is_empty());
        assert!(cache.predictions().len() <= 5); // max_predictions = 5

        // Predictions should be sorted by probability (highest first)
        for i in 1..cache.predictions().len() {
            assert!(
                cache.predictions()[i-1].probability >= cache.predictions()[i].probability,
                "Predictions should be sorted by probability"
            );
        }
    }

    #[test]
    fn test_cache_hit_tracking() {
        let mut cache = PredictiveCache::new(PredictiveCacheConfig::default());
        cache.set_distribution(WinDistribution::default());

        // Mark Loss prediction as loaded (most common outcome)
        if let Some(pred) = cache.predictions.iter_mut().find(|p| p.tier == WinTier::Loss) {
            pred.assets_loaded = true;
        }

        // Spin result: loss — should be a hit
        let hit = cache.on_spin_result(0.0);
        assert!(hit);
        assert_eq!(cache.stats().cache_hits, 1);

        // Spin result: jackpot — unlikely to be cached
        let hit = cache.on_spin_result(5000.0);
        assert!(!hit);
        assert_eq!(cache.stats().cache_misses, 1);

        // Hit rate should be 50%
        assert!((cache.stats().hit_rate - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_asset_preload_list() {
        let mut cache = PredictiveCache::new(PredictiveCacheConfig::default());
        cache.set_distribution(WinDistribution::default());

        // Map assets to the loss tier
        if !cache.predictions.is_empty() {
            let tier = cache.predictions[0].tier;
            cache.map_tier_assets(tier, vec!["settle_01.wav".to_string()]);
        }

        let to_load = cache.assets_to_preload();
        assert!(to_load.contains(&"settle_01.wav"));

        // Mark as loaded — should no longer appear in preload list
        cache.mark_loaded("settle_01.wav");
        let to_load = cache.assets_to_preload();
        assert!(!to_load.contains(&"settle_01.wav"));
    }

    #[test]
    fn test_predictive_dsp() {
        let mut dsp = PredictiveDsp::new(48000);

        assert!(!dsp.is_warmed(WinTier::BigWin));

        dsp.pre_warm(WinTier::BigWin, HashMap::new());
        assert!(dsp.is_warmed(WinTier::BigWin));

        let savings = dsp.latency_savings_ms(WinTier::BigWin);
        assert!(savings > 0.0);

        dsp.clear();
        assert!(!dsp.is_warmed(WinTier::BigWin));
    }

    #[test]
    fn test_dsp_latency_savings_scale_with_tier() {
        let mut dsp = PredictiveDsp::new(48000);

        dsp.pre_warm(WinTier::SmallWin, HashMap::new());
        dsp.pre_warm(WinTier::BigWin, HashMap::new());
        dsp.pre_warm(WinTier::Jackpot, HashMap::new());

        let small = dsp.latency_savings_ms(WinTier::SmallWin);
        let big = dsp.latency_savings_ms(WinTier::BigWin);
        let jackpot = dsp.latency_savings_ms(WinTier::Jackpot);

        // Higher tiers should save more latency (more complex audio chains)
        assert!(big > small);
        assert!(jackpot > big);
    }

    #[test]
    fn test_memory_budget_respected() {
        let config = PredictiveCacheConfig {
            max_memory_bytes: 200 * 1024, // Only 200KB — very tight
            ..Default::default()
        };
        let mut cache = PredictiveCache::new(config);
        cache.set_distribution(WinDistribution::default());

        // With such a tight budget, should have fewer predictions
        let total_est: usize = cache.predictions().iter().map(|p| p.memory_cost).sum();
        assert!(total_est <= 200 * 1024, "Memory budget exceeded: {} > {}", total_est, 200 * 1024);
    }

    #[test]
    fn test_win_tier_ordering() {
        assert!(WinTier::Loss < WinTier::SubWin);
        assert!(WinTier::SubWin < WinTier::SmallWin);
        assert!(WinTier::BigWin < WinTier::MegaWin);
        assert!(WinTier::MegaWin < WinTier::Jackpot);
    }
}
