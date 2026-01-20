//! Stability System
//!
//! 7 mechanisms to prevent erratic layer behavior:
//! 1. Global Cooldown - minimum time between any level change
//! 2. Rule Cooldowns - per-rule cooldown timers
//! 3. Level Hold - lock level for duration after change
//! 4. Level Inertia - resistance to change (higher = harder to move)
//! 5. Decay - natural drift back to baseline over time
//! 6. Momentum Buffer - smooth out rapid signal changes
//! 7. Prediction - anticipate future level based on trends

use crate::context::LayerId;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Stability configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StabilityConfig {
    /// Global cooldown between any level change (ms)
    #[serde(default = "default_global_cooldown")]
    pub global_cooldown_ms: u32,
    /// Default hold duration after level change (ms)
    #[serde(default = "default_hold_duration")]
    pub default_hold_ms: u32,
    /// Level inertia factors (per level L1-L5)
    #[serde(default = "default_inertia_factors")]
    pub level_inertia: [f32; 5],
    /// Decay configuration
    #[serde(default)]
    pub decay: DecayConfig,
    /// Momentum buffer configuration
    #[serde(default)]
    pub momentum_buffer: MomentumBufferConfig,
    /// Prediction configuration
    #[serde(default)]
    pub prediction: PredictionConfig,
}

fn default_global_cooldown() -> u32 {
    500
}
fn default_hold_duration() -> u32 {
    2000
}
fn default_inertia_factors() -> [f32; 5] {
    [1.0, 1.2, 1.5, 1.8, 2.0]
}

impl Default for StabilityConfig {
    fn default() -> Self {
        Self {
            global_cooldown_ms: 500,
            default_hold_ms: 2000,
            level_inertia: [1.0, 1.2, 1.5, 1.8, 2.0],
            decay: DecayConfig::default(),
            momentum_buffer: MomentumBufferConfig::default(),
            prediction: PredictionConfig::default(),
        }
    }
}

/// Decay configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecayConfig {
    /// Whether decay is enabled
    #[serde(default)]
    pub enabled: bool,
    /// Baseline level to decay towards
    #[serde(default = "default_baseline")]
    pub baseline_level: LayerId,
    /// Time before decay starts (ms)
    #[serde(default = "default_decay_delay")]
    pub decay_delay_ms: u32,
    /// Decay rate (levels per second)
    #[serde(default = "default_decay_rate")]
    pub decay_rate: f32,
    /// Whether decay is paused during hold
    #[serde(default = "default_true")]
    pub pause_during_hold: bool,
}

fn default_baseline() -> LayerId {
    1
}
fn default_decay_delay() -> u32 {
    5000
}
fn default_decay_rate() -> f32 {
    0.5
}
fn default_true() -> bool {
    true
}

impl Default for DecayConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            baseline_level: 1,
            decay_delay_ms: 5000,
            decay_rate: 0.5,
            pause_during_hold: true,
        }
    }
}

/// Momentum buffer configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MomentumBufferConfig {
    /// Whether momentum buffer is enabled
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Buffer size (number of samples to average)
    #[serde(default = "default_buffer_size")]
    pub buffer_size: usize,
    /// Threshold for significant change
    #[serde(default = "default_threshold")]
    pub change_threshold: f32,
}

fn default_buffer_size() -> usize {
    10
}
fn default_threshold() -> f32 {
    0.3
}

impl Default for MomentumBufferConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            buffer_size: 10,
            change_threshold: 0.3,
        }
    }
}

/// Prediction configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PredictionConfig {
    /// Whether prediction is enabled
    #[serde(default)]
    pub enabled: bool,
    /// Prediction horizon (ms)
    #[serde(default = "default_horizon")]
    pub horizon_ms: u32,
    /// Confidence threshold for prediction
    #[serde(default = "default_confidence")]
    pub confidence_threshold: f32,
}

fn default_horizon() -> u32 {
    2000
}
fn default_confidence() -> f32 {
    0.7
}

impl Default for PredictionConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            horizon_ms: 2000,
            confidence_threshold: 0.7,
        }
    }
}

/// Prediction result
#[derive(Debug, Clone, Copy)]
pub struct Prediction {
    /// Predicted target level
    pub predicted_level: LayerId,
    /// Confidence (0.0 - 1.0)
    pub confidence: f32,
    /// Estimated time to reach (ms)
    pub eta_ms: u32,
}

/// Stability state (mutable runtime state)
#[derive(Debug)]
pub struct StabilityState {
    /// Configuration
    config: StabilityConfig,
    /// Global cooldown expiry time
    global_cooldown_until: Option<u64>,
    /// Per-rule cooldown timers
    rule_cooldowns: HashMap<String, u64>,
    /// Level hold expiry time
    level_hold_until: Option<u64>,
    /// Current held level (None if not holding)
    held_level: Option<LayerId>,
    /// Last level change time (for decay)
    last_change_time: u64,
    /// Momentum buffer (circular)
    momentum_buffer: Vec<f32>,
    /// Momentum buffer write index
    momentum_index: usize,
    /// Smoothed momentum value
    smoothed_momentum: f32,
    /// Level history for prediction (circular)
    level_history: Vec<(u64, LayerId)>,
    /// Level history write index
    history_index: usize,
    /// Last prediction
    last_prediction: Option<Prediction>,
    /// Fractional decay accumulator
    decay_accumulator: f32,
}

impl StabilityState {
    /// Create a new stability state
    pub fn new(config: StabilityConfig) -> Self {
        let buffer_size = config.momentum_buffer.buffer_size;
        Self {
            config,
            global_cooldown_until: None,
            rule_cooldowns: HashMap::new(),
            level_hold_until: None,
            held_level: None,
            last_change_time: 0,
            momentum_buffer: vec![0.0; buffer_size],
            momentum_index: 0,
            smoothed_momentum: 0.0,
            level_history: vec![(0, 0); 20], // Keep last 20 level changes
            history_index: 0,
            last_prediction: None,
            decay_accumulator: 0.0,
        }
    }

    /// Update configuration
    pub fn set_config(&mut self, config: StabilityConfig) {
        let old_buffer_size = self.config.momentum_buffer.buffer_size;
        let new_buffer_size = config.momentum_buffer.buffer_size;

        if old_buffer_size != new_buffer_size {
            self.momentum_buffer = vec![0.0; new_buffer_size];
            self.momentum_index = 0;
        }

        self.config = config;
    }

    /// Check if global cooldown is active
    pub fn is_global_cooldown_active(&self, current_time_ms: u64) -> bool {
        self.global_cooldown_until
            .is_some_and(|until| current_time_ms < until)
    }

    /// Check if a rule's cooldown is active
    pub fn is_rule_cooldown_active(&self, rule_id: &str, current_time_ms: u64) -> bool {
        self.rule_cooldowns
            .get(rule_id)
            .is_some_and(|until| current_time_ms < *until)
    }

    /// Check if level hold is active
    pub fn is_hold_active(&self, current_time_ms: u64) -> bool {
        self.level_hold_until
            .is_some_and(|until| current_time_ms < until)
    }

    /// Get remaining hold time (ms)
    pub fn hold_remaining_ms(&self, current_time_ms: u64) -> u32 {
        self.level_hold_until
            .map(|until| until.saturating_sub(current_time_ms) as u32)
            .unwrap_or(0)
    }

    /// Get held level if hold is active
    pub fn get_held_level(&self, current_time_ms: u64) -> Option<LayerId> {
        if self.is_hold_active(current_time_ms) {
            self.held_level
        } else {
            None
        }
    }

    /// Start global cooldown
    pub fn start_global_cooldown(&mut self, current_time_ms: u64) {
        self.global_cooldown_until = Some(current_time_ms + self.config.global_cooldown_ms as u64);
    }

    /// Start rule cooldown
    pub fn start_rule_cooldown(&mut self, rule_id: &str, cooldown_ms: u32, current_time_ms: u64) {
        if cooldown_ms > 0 {
            self.rule_cooldowns
                .insert(rule_id.to_string(), current_time_ms + cooldown_ms as u64);
        }
    }

    /// Start level hold
    pub fn start_hold(&mut self, level: LayerId, duration_ms: u32, current_time_ms: u64) {
        let duration = if duration_ms > 0 {
            duration_ms
        } else {
            self.config.default_hold_ms
        };
        self.level_hold_until = Some(current_time_ms + duration as u64);
        self.held_level = Some(level);
    }

    /// Release hold
    pub fn release_hold(&mut self) {
        self.level_hold_until = None;
        self.held_level = None;
    }

    /// Record a level change (for decay/prediction)
    pub fn record_level_change(&mut self, level: LayerId, current_time_ms: u64) {
        self.last_change_time = current_time_ms;
        self.decay_accumulator = 0.0;

        // Add to history
        self.level_history[self.history_index] = (current_time_ms, level);
        self.history_index = (self.history_index + 1) % self.level_history.len();
    }

    /// Get level inertia factor
    pub fn get_inertia(&self, level: LayerId) -> f32 {
        let idx = (level as usize).min(4);
        self.config.level_inertia[idx]
    }

    /// Check if level change passes inertia threshold
    pub fn passes_inertia(&self, current_level: LayerId, signal_strength: f32) -> bool {
        let inertia = self.get_inertia(current_level);
        signal_strength >= inertia * 0.5 // Scale threshold by inertia
    }

    /// Update momentum buffer
    pub fn update_momentum(&mut self, value: f32) {
        if !self.config.momentum_buffer.enabled {
            self.smoothed_momentum = value;
            return;
        }

        self.momentum_buffer[self.momentum_index] = value;
        self.momentum_index = (self.momentum_index + 1) % self.momentum_buffer.len();

        // Calculate smoothed average
        let sum: f32 = self.momentum_buffer.iter().sum();
        self.smoothed_momentum = sum / self.momentum_buffer.len() as f32;
    }

    /// Get smoothed momentum
    pub fn smoothed_momentum(&self) -> f32 {
        self.smoothed_momentum
    }

    /// Check if momentum change is significant
    pub fn is_momentum_significant(&self, new_momentum: f32) -> bool {
        (new_momentum - self.smoothed_momentum).abs() >= self.config.momentum_buffer.change_threshold
    }

    /// Calculate decay
    pub fn calculate_decay(
        &mut self,
        current_level: LayerId,
        current_time_ms: u64,
        delta_ms: u32,
    ) -> Option<LayerId> {
        if !self.config.decay.enabled {
            return None;
        }

        // Check if decay is paused during hold
        if self.config.decay.pause_during_hold && self.is_hold_active(current_time_ms) {
            return None;
        }

        // Check if we're at baseline
        if current_level == self.config.decay.baseline_level {
            return None;
        }

        // Check if decay delay has passed
        let time_since_change = current_time_ms.saturating_sub(self.last_change_time);
        if time_since_change < self.config.decay.decay_delay_ms as u64 {
            return None;
        }

        // Accumulate decay
        let decay_per_ms = self.config.decay.decay_rate / 1000.0;
        self.decay_accumulator += decay_per_ms * delta_ms as f32;

        // Check if we've accumulated enough to change level
        if self.decay_accumulator >= 1.0 {
            self.decay_accumulator -= 1.0;

            let baseline = self.config.decay.baseline_level;
            if current_level > baseline {
                Some(current_level - 1)
            } else if current_level < baseline {
                Some(current_level + 1)
            } else {
                None
            }
        } else {
            None
        }
    }

    /// Calculate prediction
    pub fn calculate_prediction(&mut self, current_level: LayerId, current_time_ms: u64) -> Option<Prediction> {
        if !self.config.prediction.enabled {
            return None;
        }

        // Need at least 3 data points for meaningful prediction
        let mut recent: Vec<(u64, LayerId)> = self
            .level_history
            .iter()
            .filter(|(t, _)| *t > 0 && current_time_ms.saturating_sub(*t) < 10000)
            .copied()
            .collect();

        if recent.len() < 3 {
            return None;
        }

        recent.sort_by_key(|(t, _)| *t);

        // Simple linear regression on level changes
        let n = recent.len() as f32;
        let sum_x: f32 = recent.iter().map(|(t, _)| *t as f32).sum();
        let sum_y: f32 = recent.iter().map(|(_, l)| *l as f32).sum();
        let sum_xy: f32 = recent.iter().map(|(t, l)| *t as f32 * *l as f32).sum();
        let sum_xx: f32 = recent.iter().map(|(t, _)| (*t as f32).powi(2)).sum();

        let slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x.powi(2));

        if slope.abs() < 0.0001 {
            return None; // No significant trend
        }

        // Predict level at horizon
        let _future_time = current_time_ms + self.config.prediction.horizon_ms as u64;
        let predicted = current_level as f32 + slope * self.config.prediction.horizon_ms as f32;
        let predicted_level = predicted.round().clamp(0.0, 4.0) as LayerId;

        // Calculate confidence based on R² of the regression
        let mean_y = sum_y / n;
        let ss_tot: f32 = recent.iter().map(|(_, l)| (*l as f32 - mean_y).powi(2)).sum();
        let intercept = (sum_y - slope * sum_x) / n;
        let ss_res: f32 = recent
            .iter()
            .map(|(t, l)| {
                let predicted = slope * *t as f32 + intercept;
                (*l as f32 - predicted).powi(2)
            })
            .sum();

        let r_squared = if ss_tot > 0.0 {
            1.0 - (ss_res / ss_tot)
        } else {
            0.0
        };

        let confidence = r_squared.clamp(0.0, 1.0);

        if confidence >= self.config.prediction.confidence_threshold {
            let prediction = Prediction {
                predicted_level,
                confidence,
                eta_ms: self.config.prediction.horizon_ms,
            };
            self.last_prediction = Some(prediction);
            Some(prediction)
        } else {
            self.last_prediction = None;
            None
        }
    }

    /// Get last prediction
    pub fn last_prediction(&self) -> Option<&Prediction> {
        self.last_prediction.as_ref()
    }

    /// Can level change occur? (checks all stability mechanisms)
    pub fn can_change_level(
        &self,
        rule_id: &str,
        requires_hold_expired: bool,
        current_time_ms: u64,
    ) -> bool {
        // Check global cooldown
        if self.is_global_cooldown_active(current_time_ms) {
            return false;
        }

        // Check rule cooldown
        if self.is_rule_cooldown_active(rule_id, current_time_ms) {
            return false;
        }

        // Check hold requirement
        if requires_hold_expired && self.is_hold_active(current_time_ms) {
            return false;
        }

        true
    }

    /// Reset all stability state
    pub fn reset(&mut self) {
        self.global_cooldown_until = None;
        self.rule_cooldowns.clear();
        self.level_hold_until = None;
        self.held_level = None;
        self.last_change_time = 0;
        self.momentum_buffer.fill(0.0);
        self.momentum_index = 0;
        self.smoothed_momentum = 0.0;
        self.level_history.fill((0, 0));
        self.history_index = 0;
        self.last_prediction = None;
        self.decay_accumulator = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_global_cooldown() {
        let config = StabilityConfig {
            global_cooldown_ms: 500,
            ..Default::default()
        };
        let mut state = StabilityState::new(config);

        assert!(!state.is_global_cooldown_active(0));

        state.start_global_cooldown(100);
        assert!(state.is_global_cooldown_active(200));
        assert!(state.is_global_cooldown_active(599));
        assert!(!state.is_global_cooldown_active(600));
        assert!(!state.is_global_cooldown_active(700));
    }

    #[test]
    fn test_rule_cooldown() {
        let config = StabilityConfig::default();
        let mut state = StabilityState::new(config);

        state.start_rule_cooldown("test_rule", 1000, 100);
        assert!(state.is_rule_cooldown_active("test_rule", 500));
        assert!(state.is_rule_cooldown_active("test_rule", 1099));
        assert!(!state.is_rule_cooldown_active("test_rule", 1100));
        assert!(!state.is_rule_cooldown_active("other_rule", 500));
    }

    #[test]
    fn test_level_hold() {
        let config = StabilityConfig::default();
        let mut state = StabilityState::new(config);

        state.start_hold(3, 2000, 100);
        assert!(state.is_hold_active(500));
        assert_eq!(state.get_held_level(500), Some(3));
        assert_eq!(state.hold_remaining_ms(1100), 1000);
        assert!(state.is_hold_active(2099));
        assert!(!state.is_hold_active(2100));
        assert_eq!(state.get_held_level(2200), None);
    }

    #[test]
    fn test_inertia() {
        let config = StabilityConfig {
            level_inertia: [1.0, 1.2, 1.5, 1.8, 2.0],
            ..Default::default()
        };
        let state = StabilityState::new(config);

        assert!((state.get_inertia(0) - 1.0).abs() < 0.01);
        assert!((state.get_inertia(2) - 1.5).abs() < 0.01);
        assert!((state.get_inertia(4) - 2.0).abs() < 0.01);
    }

    #[test]
    fn test_momentum_buffer() {
        let config = StabilityConfig {
            momentum_buffer: MomentumBufferConfig {
                enabled: true,
                buffer_size: 5,
                change_threshold: 0.3,
            },
            ..Default::default()
        };
        let mut state = StabilityState::new(config);

        // Fill buffer with same value
        for _ in 0..5 {
            state.update_momentum(0.5);
        }
        assert!((state.smoothed_momentum() - 0.5).abs() < 0.01);

        // Large change should be significant
        assert!(state.is_momentum_significant(0.9));

        // Small change should not be significant
        assert!(!state.is_momentum_significant(0.55));
    }

    #[test]
    fn test_decay() {
        let config = StabilityConfig {
            decay: DecayConfig {
                enabled: true,
                baseline_level: 1,
                decay_delay_ms: 1000,
                decay_rate: 2.0, // 2 levels per second
                pause_during_hold: true,
            },
            ..Default::default()
        };
        let mut state = StabilityState::new(config);

        state.record_level_change(4, 0);

        // Before decay delay
        assert_eq!(state.calculate_decay(4, 500, 500), None);

        // After decay delay, should start decaying
        assert_eq!(state.calculate_decay(4, 1500, 500), Some(3));

        // At baseline, no decay
        assert_eq!(state.calculate_decay(1, 2000, 500), None);
    }

    #[test]
    fn test_can_change_level() {
        let config = StabilityConfig {
            global_cooldown_ms: 500,
            ..Default::default()
        };
        let mut state = StabilityState::new(config);

        // Initially should be able to change
        assert!(state.can_change_level("rule1", false, 0));

        // Start global cooldown at time 100
        state.start_global_cooldown(100);
        // At time 200, global cooldown is active (until 600)
        assert!(!state.can_change_level("rule1", false, 200));
        // At time 700, global cooldown expired
        assert!(state.can_change_level("rule1", false, 700));

        // Start rule cooldown for rule1 (1000ms from time 800)
        state.start_rule_cooldown("rule1", 1000, 800);
        // At time 900, rule1 cooldown is active (until 1800), but rule2 is free
        assert!(!state.can_change_level("rule1", false, 900));
        assert!(state.can_change_level("rule2", false, 900));

        // Start hold at time 2000, duration 2000ms
        state.start_hold(3, 2000, 2000);
        // At time 2500, hold is active - requires_hold_expired=true should block
        assert!(!state.can_change_level("rule2", true, 2500));
        // requires_hold_expired=false should allow
        assert!(state.can_change_level("rule2", false, 2500));
    }
}
