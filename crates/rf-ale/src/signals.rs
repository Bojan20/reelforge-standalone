//! Signal System
//!
//! Signals are normalized metrics that drive the ALE. Each signal has:
//! - A raw value from the game
//! - A normalization function (linear, sigmoid, asymptotic)
//! - Optional derived signals (momentum, velocity)

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Normalization mode for signals
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum NormalizationMode {
    /// Linear mapping: (value - min) / (max - min)
    #[default]
    Linear,
    /// Sigmoid: 1 / (1 + e^(-k*(x-mid)))
    Sigmoid,
    /// Asymptotic: 1 - e^(-k*x)
    Asymptotic,
    /// No normalization (pass-through)
    None,
}

/// Signal definition with normalization parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalDefinition {
    /// Signal identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Normalization mode
    #[serde(default)]
    pub normalization: NormalizationMode,
    /// Minimum value for linear normalization
    #[serde(default)]
    pub min: f32,
    /// Maximum value for linear normalization
    #[serde(default = "default_max")]
    pub max: f32,
    /// Midpoint for sigmoid normalization
    #[serde(default)]
    pub midpoint: f32,
    /// Steepness factor for sigmoid/asymptotic
    #[serde(default = "default_steepness")]
    pub steepness: f32,
    /// Whether this is a derived signal (momentum, velocity)
    #[serde(default)]
    pub derived: bool,
    /// Source signal for derived signals
    #[serde(default)]
    pub source_signal: Option<String>,
}

fn default_max() -> f32 {
    1.0
}

fn default_steepness() -> f32 {
    1.0
}

impl SignalDefinition {
    /// Create a new linear signal
    pub fn linear(id: &str, name: &str, min: f32, max: f32) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            normalization: NormalizationMode::Linear,
            min,
            max,
            midpoint: 0.0,
            steepness: 1.0,
            derived: false,
            source_signal: None,
        }
    }

    /// Create a sigmoid-normalized signal
    pub fn sigmoid(id: &str, name: &str, midpoint: f32, steepness: f32) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            normalization: NormalizationMode::Sigmoid,
            min: 0.0,
            max: 1.0,
            midpoint,
            steepness,
            derived: false,
            source_signal: None,
        }
    }

    /// Create an asymptotic-normalized signal
    pub fn asymptotic(id: &str, name: &str, steepness: f32) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            normalization: NormalizationMode::Asymptotic,
            min: 0.0,
            max: 1.0,
            midpoint: 0.0,
            steepness,
            derived: false,
            source_signal: None,
        }
    }

    /// Create a momentum signal (EMA of source)
    pub fn momentum(id: &str, source: &str) -> Self {
        Self {
            id: id.to_string(),
            name: format!("{} Momentum", source),
            normalization: NormalizationMode::None,
            min: 0.0,
            max: 1.0,
            midpoint: 0.0,
            steepness: 1.0,
            derived: true,
            source_signal: Some(source.to_string()),
        }
    }

    /// Create a velocity signal (rate of change)
    pub fn velocity(id: &str, source: &str) -> Self {
        Self {
            id: id.to_string(),
            name: format!("{} Velocity", source),
            normalization: NormalizationMode::None,
            min: -1.0,
            max: 1.0,
            midpoint: 0.0,
            steepness: 1.0,
            derived: true,
            source_signal: Some(source.to_string()),
        }
    }

    /// Normalize a raw value
    #[inline]
    pub fn normalize(&self, raw: f32) -> f32 {
        match self.normalization {
            NormalizationMode::Linear => {
                let range = self.max - self.min;
                if range.abs() < f32::EPSILON {
                    return 0.0;
                }
                ((raw - self.min) / range).clamp(0.0, 1.0)
            }
            NormalizationMode::Sigmoid => {
                let x = -self.steepness * (raw - self.midpoint);
                1.0 / (1.0 + x.exp())
            }
            NormalizationMode::Asymptotic => {
                let x = -self.steepness * raw;
                (1.0 - x.exp()).clamp(0.0, 1.0)
            }
            NormalizationMode::None => raw,
        }
    }
}

/// Built-in signal IDs
pub mod builtins {
    pub const WIN_TIER: &str = "winTier";
    pub const WIN_XBET: &str = "winXbet";
    pub const CONSECUTIVE_WINS: &str = "consecutiveWins";
    pub const CONSECUTIVE_LOSSES: &str = "consecutiveLosses";
    pub const WIN_STREAK_LENGTH: &str = "winStreakLength";
    pub const LOSS_STREAK_LENGTH: &str = "lossStreakLength";
    pub const BALANCE_TREND: &str = "balanceTrend";
    pub const SESSION_PROFIT: &str = "sessionProfit";
    pub const FEATURE_PROGRESS: &str = "featureProgress";
    pub const MULTIPLIER: &str = "multiplier";
    pub const NEAR_MISS_INTENSITY: &str = "nearMissIntensity";
    pub const ANTICIPATION_LEVEL: &str = "anticipationLevel";
    pub const CASCADE_DEPTH: &str = "cascadeDepth";
    pub const RESPINS_REMAINING: &str = "respinsRemaining";
    pub const SPINS_IN_FEATURE: &str = "spinsInFeature";
    pub const TOTAL_FEATURE_SPINS: &str = "totalFeatureSpins";
    pub const JACKPOT_PROXIMITY: &str = "jackpotProximity";
    pub const TURBO_MODE: &str = "turboMode";

    // Derived signals
    pub const MOMENTUM: &str = "momentum";
    pub const VELOCITY: &str = "velocity";
}

/// Current signal values (pre-allocated, no heap allocations during update)
#[derive(Debug, Clone)]
pub struct MetricSignals {
    /// Signal values by ID hash (for fast lookup)
    values: HashMap<u32, f32>,
    /// Signal history for momentum/velocity (circular buffer indices)
    history_index: usize,
    /// Momentum value (EMA)
    momentum: f32,
    /// Velocity value (rate of change)
    velocity: f32,
    /// EMA alpha for momentum calculation
    ema_alpha: f32,
    /// Previous average for velocity calculation
    prev_avg: f32,
}

impl Default for MetricSignals {
    fn default() -> Self {
        Self::new()
    }
}

impl MetricSignals {
    pub fn new() -> Self {
        Self {
            values: HashMap::with_capacity(32),
            history_index: 0,
            momentum: 0.0,
            velocity: 0.0,
            ema_alpha: 0.2, // ~5-sample EMA
            prev_avg: 0.0,
        }
    }

    /// Hash a signal ID for fast lookup
    #[inline]
    fn hash_id(id: &str) -> u32 {
        // Simple FNV-1a hash
        let mut hash: u32 = 2166136261;
        for byte in id.bytes() {
            hash ^= byte as u32;
            hash = hash.wrapping_mul(16777619);
        }
        hash
    }

    /// Set a signal value
    #[inline]
    pub fn set(&mut self, id: &str, value: f32) {
        let hash = Self::hash_id(id);
        self.values.insert(hash, value);
    }

    /// Get a signal value
    #[inline]
    pub fn get(&self, id: &str) -> f32 {
        let hash = Self::hash_id(id);
        self.values.get(&hash).copied().unwrap_or(0.0)
    }

    /// Check if a signal exists
    #[inline]
    pub fn has(&self, id: &str) -> bool {
        let hash = Self::hash_id(id);
        self.values.contains_key(&hash)
    }

    /// Update derived signals (momentum, velocity)
    pub fn update_derived(&mut self, primary_signal: &str) {
        let current = self.get(primary_signal);

        // Update momentum (EMA)
        self.momentum = self.ema_alpha * current + (1.0 - self.ema_alpha) * self.momentum;
        self.set(builtins::MOMENTUM, self.momentum);

        // Update velocity (rate of change)
        self.velocity = current - self.prev_avg;
        self.prev_avg = self.momentum;
        self.set(builtins::VELOCITY, self.velocity);

        self.history_index = (self.history_index + 1) % crate::SIGNAL_HISTORY_DEPTH;
    }

    /// Batch update multiple signals
    pub fn update_batch(&mut self, updates: &[(&str, f32)]) {
        for (id, value) in updates {
            self.set(id, *value);
        }
    }

    /// Get momentum value
    #[inline]
    pub fn momentum(&self) -> f32 {
        self.momentum
    }

    /// Get velocity value
    #[inline]
    pub fn velocity(&self) -> f32 {
        self.velocity
    }

    /// Clear all signals
    pub fn clear(&mut self) {
        self.values.clear();
        self.momentum = 0.0;
        self.velocity = 0.0;
        self.prev_avg = 0.0;
        self.history_index = 0;
    }
}

/// Signal registry with definitions
#[derive(Debug, Clone, Default)]
pub struct SignalRegistry {
    definitions: HashMap<String, SignalDefinition>,
}

impl SignalRegistry {
    pub fn new() -> Self {
        Self {
            definitions: HashMap::new(),
        }
    }

    /// Create registry with built-in signals
    pub fn with_builtins() -> Self {
        let mut registry = Self::new();

        // Win-related signals
        registry.register(SignalDefinition::linear(
            builtins::WIN_TIER,
            "Win Tier",
            0.0,
            5.0,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::WIN_XBET,
            "Win Multiplier (xBet)",
            0.05,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::CONSECUTIVE_WINS,
            "Consecutive Wins",
            0.3,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::CONSECUTIVE_LOSSES,
            "Consecutive Losses",
            0.2,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::WIN_STREAK_LENGTH,
            "Win Streak Length",
            0.25,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::LOSS_STREAK_LENGTH,
            "Loss Streak Length",
            0.15,
        ));

        // Balance signals
        registry.register(SignalDefinition::sigmoid(
            builtins::BALANCE_TREND,
            "Balance Trend",
            0.0,
            2.0,
        ));
        registry.register(SignalDefinition::sigmoid(
            builtins::SESSION_PROFIT,
            "Session Profit",
            0.0,
            0.5,
        ));

        // Feature signals
        registry.register(SignalDefinition::linear(
            builtins::FEATURE_PROGRESS,
            "Feature Progress",
            0.0,
            1.0,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::MULTIPLIER,
            "Multiplier",
            0.1,
        ));
        registry.register(SignalDefinition::linear(
            builtins::NEAR_MISS_INTENSITY,
            "Near Miss Intensity",
            0.0,
            1.0,
        ));
        registry.register(SignalDefinition::linear(
            builtins::ANTICIPATION_LEVEL,
            "Anticipation Level",
            0.0,
            1.0,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::CASCADE_DEPTH,
            "Cascade Depth",
            0.3,
        ));
        registry.register(SignalDefinition::linear(
            builtins::RESPINS_REMAINING,
            "Respins Remaining",
            0.0,
            10.0,
        ));
        registry.register(SignalDefinition::linear(
            builtins::SPINS_IN_FEATURE,
            "Spins in Feature",
            0.0,
            1.0,
        ));
        registry.register(SignalDefinition::linear(
            builtins::TOTAL_FEATURE_SPINS,
            "Total Feature Spins",
            0.0,
            1.0,
        ));
        registry.register(SignalDefinition::asymptotic(
            builtins::JACKPOT_PROXIMITY,
            "Jackpot Proximity",
            0.5,
        ));
        registry.register(SignalDefinition::linear(
            builtins::TURBO_MODE,
            "Turbo Mode",
            0.0,
            1.0,
        ));

        // Derived signals
        registry.register(SignalDefinition::momentum(
            builtins::MOMENTUM,
            builtins::WIN_TIER,
        ));
        registry.register(SignalDefinition::velocity(
            builtins::VELOCITY,
            builtins::WIN_TIER,
        ));

        registry
    }

    /// Register a signal definition
    pub fn register(&mut self, def: SignalDefinition) {
        self.definitions.insert(def.id.clone(), def);
    }

    /// Get a signal definition
    pub fn get(&self, id: &str) -> Option<&SignalDefinition> {
        self.definitions.get(id)
    }

    /// Normalize a raw value for a signal
    pub fn normalize(&self, id: &str, raw: f32) -> f32 {
        self.definitions
            .get(id)
            .map(|def| def.normalize(raw))
            .unwrap_or(raw)
    }

    /// List all signal IDs
    pub fn signal_ids(&self) -> impl Iterator<Item = &str> {
        self.definitions.keys().map(|s| s.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear_normalization() {
        let def = SignalDefinition::linear("test", "Test", 0.0, 10.0);
        assert!((def.normalize(0.0) - 0.0).abs() < 0.001);
        assert!((def.normalize(5.0) - 0.5).abs() < 0.001);
        assert!((def.normalize(10.0) - 1.0).abs() < 0.001);
        assert!((def.normalize(15.0) - 1.0).abs() < 0.001); // Clamped
    }

    #[test]
    fn test_sigmoid_normalization() {
        let def = SignalDefinition::sigmoid("test", "Test", 5.0, 1.0);
        assert!(def.normalize(0.0) < 0.1);
        assert!((def.normalize(5.0) - 0.5).abs() < 0.001);
        assert!(def.normalize(10.0) > 0.9);
    }

    #[test]
    fn test_asymptotic_normalization() {
        let def = SignalDefinition::asymptotic("test", "Test", 0.5);
        assert!((def.normalize(0.0) - 0.0).abs() < 0.001);
        assert!(def.normalize(5.0) > 0.9);
    }

    #[test]
    fn test_metric_signals() {
        let mut signals = MetricSignals::new();
        signals.set(builtins::WIN_TIER, 3.0);
        assert!((signals.get(builtins::WIN_TIER) - 3.0).abs() < 0.001);
        assert!((signals.get("nonexistent") - 0.0).abs() < 0.001);
    }
}
