//! Math Model — Probability distribution for Math-Driven mode

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Math model for realistic probability distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathModel {
    /// Target RTP (e.g., 0.965 = 96.5%)
    pub target_rtp: f64,

    /// Symbol weights per reel
    pub symbol_weights: SymbolWeights,

    /// Feature trigger frequencies
    pub feature_frequencies: FeatureFrequencies,

    /// Win distribution parameters
    pub win_distribution: WinDistributionParams,
}

impl MathModel {
    /// Create a basic math model
    pub fn new(target_rtp: f64) -> Self {
        Self {
            target_rtp: target_rtp.clamp(0.5, 1.0),
            symbol_weights: SymbolWeights::default(),
            feature_frequencies: FeatureFrequencies::default(),
            win_distribution: WinDistributionParams::default(),
        }
    }

    /// Standard 96.5% RTP model
    pub fn standard() -> Self {
        Self::new(0.965)
    }

    /// High RTP model (97%+)
    pub fn high_rtp() -> Self {
        Self {
            target_rtp: 0.97,
            symbol_weights: SymbolWeights::default(),
            feature_frequencies: FeatureFrequencies::high_frequency(),
            win_distribution: WinDistributionParams::high_hit_rate(),
        }
    }
}

impl Default for MathModel {
    fn default() -> Self {
        Self::standard()
    }
}

/// Symbol weights per reel
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SymbolWeights {
    /// Weight map: symbol_id -> [weight_reel_0, weight_reel_1, ...]
    #[serde(default)]
    pub weights: HashMap<u32, Vec<u32>>,
}

impl SymbolWeights {
    /// Set weights for a symbol across all reels
    pub fn set(&mut self, symbol_id: u32, weights: Vec<u32>) {
        self.weights.insert(symbol_id, weights);
    }

    /// Get weights for a symbol
    pub fn get(&self, symbol_id: u32) -> Option<&Vec<u32>> {
        self.weights.get(&symbol_id)
    }

    /// Get weight for a specific symbol on a specific reel
    pub fn get_weight(&self, symbol_id: u32, reel: usize) -> u32 {
        self.weights
            .get(&symbol_id)
            .and_then(|w| w.get(reel))
            .copied()
            .unwrap_or(10) // Default weight
    }

    /// Calculate total weight for a reel
    pub fn total_weight(&self, reel: usize) -> u32 {
        self.weights
            .values()
            .filter_map(|w| w.get(reel))
            .sum()
    }
}

/// Feature trigger frequencies
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureFrequencies {
    /// Free spins trigger frequency (1 in N spins)
    pub free_spins: f64,

    /// Bonus game trigger frequency
    pub bonus: f64,

    /// Jackpot trigger frequency
    pub jackpot: f64,

    /// Near miss frequency (for anticipation)
    pub near_miss: f64,

    /// Cascade probability (after a win)
    pub cascade: f64,
}

impl FeatureFrequencies {
    /// Standard frequencies
    pub fn standard() -> Self {
        Self {
            free_spins: 0.01,   // 1 in 100
            bonus: 0.005,       // 1 in 200
            jackpot: 0.0001,    // 1 in 10,000
            near_miss: 0.15,    // 15%
            cascade: 0.30,      // 30%
        }
    }

    /// High frequency (for testing/studio mode)
    pub fn high_frequency() -> Self {
        Self {
            free_spins: 0.05,   // 1 in 20
            bonus: 0.03,        // 1 in 33
            jackpot: 0.001,     // 1 in 1,000
            near_miss: 0.25,    // 25%
            cascade: 0.50,      // 50%
        }
    }

    /// Low frequency (high volatility)
    pub fn low_frequency() -> Self {
        Self {
            free_spins: 0.005,  // 1 in 200
            bonus: 0.002,       // 1 in 500
            jackpot: 0.00005,   // 1 in 20,000
            near_miss: 0.20,    // 20%
            cascade: 0.25,      // 25%
        }
    }
}

impl Default for FeatureFrequencies {
    fn default() -> Self {
        Self::standard()
    }
}

/// Win distribution parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinDistributionParams {
    /// Base hit rate (percentage of spins that win)
    pub hit_rate: f64,

    /// Percentage of wins that are "big" (>15x)
    pub big_win_percentage: f64,

    /// Maximum win cap (bet multiplier)
    pub max_win_cap: f64,

    /// Average win size (bet multiplier)
    pub average_win_size: f64,
}

impl WinDistributionParams {
    /// Standard distribution
    pub fn standard() -> Self {
        Self {
            hit_rate: 0.28,           // 28% of spins win
            big_win_percentage: 0.05, // 5% of wins are big
            max_win_cap: 10000.0,     // 10,000x max
            average_win_size: 3.5,    // 3.5x average
        }
    }

    /// High hit rate (low volatility)
    pub fn high_hit_rate() -> Self {
        Self {
            hit_rate: 0.38,
            big_win_percentage: 0.02,
            max_win_cap: 5000.0,
            average_win_size: 2.5,
        }
    }

    /// Low hit rate (high volatility)
    pub fn low_hit_rate() -> Self {
        Self {
            hit_rate: 0.18,
            big_win_percentage: 0.10,
            max_win_cap: 25000.0,
            average_win_size: 5.0,
        }
    }
}

impl Default for WinDistributionParams {
    fn default() -> Self {
        Self::standard()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_math_model_creation() {
        let model = MathModel::standard();
        assert!((model.target_rtp - 0.965).abs() < 0.001);
    }

    #[test]
    fn test_symbol_weights() {
        let mut weights = SymbolWeights::default();
        weights.set(1, vec![10, 10, 10, 10, 10]);
        weights.set(2, vec![5, 5, 5, 5, 5]);

        assert_eq!(weights.get_weight(1, 0), 10);
        assert_eq!(weights.get_weight(2, 2), 5);
        assert_eq!(weights.total_weight(0), 15);
    }

    #[test]
    fn test_feature_frequencies() {
        let freq = FeatureFrequencies::standard();
        assert!(freq.free_spins > 0.0 && freq.free_spins < 1.0);
        assert!(freq.jackpot < freq.free_spins); // Jackpot rarer than FS
    }
}
