//! Feature execution context

use serde::{Deserialize, Serialize};

/// Context for feature activation
#[derive(Debug, Clone)]
pub struct ActivationContext {
    /// Triggering symbol count (e.g., scatter count)
    pub trigger_count: u8,

    /// Bet amount
    pub bet: f64,

    /// Current multiplier
    pub multiplier: f64,

    /// Grid state at activation
    pub grid: Vec<Vec<u32>>,

    /// Additional trigger data
    pub trigger_data: std::collections::HashMap<String, serde_json::Value>,
}

impl ActivationContext {
    /// Get scatter count (alias for trigger_count)
    pub fn scatter_count(&self) -> u8 {
        self.trigger_count
    }
}

impl ActivationContext {
    /// Create a new activation context
    pub fn new(trigger_count: u8, bet: f64) -> Self {
        Self {
            trigger_count,
            bet,
            multiplier: 1.0,
            grid: Vec::new(),
            trigger_data: Default::default(),
        }
    }

    /// Builder: set grid
    pub fn with_grid(mut self, grid: Vec<Vec<u32>>) -> Self {
        self.grid = grid;
        self
    }

    /// Builder: set multiplier
    pub fn with_multiplier(mut self, mult: f64) -> Self {
        self.multiplier = mult;
        self
    }
}

/// Context for spin processing within a feature
#[derive(Debug, Clone)]
pub struct SpinContext {
    /// Current spin number within feature
    pub spin_number: u32,

    /// Total spins in feature (if known)
    pub total_spins: Option<u32>,

    /// Current bet
    pub bet: f64,

    /// Current multiplier
    pub multiplier: f64,

    /// Accumulated win so far
    pub accumulated_win: f64,

    /// Current grid
    pub grid: Vec<Vec<u32>>,

    /// Is this a free spin?
    pub is_free: bool,

    /// Random value (0.0 - 1.0) for deterministic outcomes
    pub random: f64,
}

impl SpinContext {
    /// Create a new spin context
    pub fn new(bet: f64) -> Self {
        Self {
            spin_number: 0,
            total_spins: None,
            bet,
            multiplier: 1.0,
            accumulated_win: 0.0,
            grid: Vec::new(),
            is_free: false,
            random: 0.0,
        }
    }

    /// Set spin number
    pub fn at_spin(mut self, number: u32, total: Option<u32>) -> Self {
        self.spin_number = number;
        self.total_spins = total;
        self
    }

    /// Set grid
    pub fn with_grid(mut self, grid: Vec<Vec<u32>>) -> Self {
        self.grid = grid;
        self
    }

    /// Set multiplier
    pub fn with_multiplier(mut self, mult: f64) -> Self {
        self.multiplier = mult;
        self
    }

    /// Mark as free spin
    pub fn as_free(mut self) -> Self {
        self.is_free = true;
        self
    }

    /// Set random value
    pub fn with_random(mut self, r: f64) -> Self {
        self.random = r.clamp(0.0, 1.0);
        self
    }

    /// Check if this is the last spin
    pub fn is_last_spin(&self) -> bool {
        self.total_spins
            .map(|t| self.spin_number >= t)
            .unwrap_or(false)
    }

    /// Get remaining spins
    pub fn remaining_spins(&self) -> Option<u32> {
        self.total_spins.map(|t| t.saturating_sub(self.spin_number))
    }
}

impl Default for SpinContext {
    fn default() -> Self {
        Self::new(1.0)
    }
}

/// Snapshot of feature state for serialization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureSnapshot {
    /// Feature ID
    pub feature_id: String,

    /// Is active?
    pub is_active: bool,

    /// Current step/spin
    pub current_step: u32,

    /// Total steps/spins
    pub total_steps: Option<u32>,

    /// Current multiplier
    pub multiplier: f64,

    /// Accumulated win
    pub accumulated_win: f64,

    /// Additional state data
    #[serde(default)]
    pub data: std::collections::HashMap<String, serde_json::Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_activation_context() {
        let ctx = ActivationContext::new(3, 1.0)
            .with_multiplier(2.0)
            .with_grid(vec![vec![1, 2, 3]]);

        assert_eq!(ctx.trigger_count, 3);
        assert!((ctx.multiplier - 2.0).abs() < 0.001);
        assert!(!ctx.grid.is_empty());
    }

    #[test]
    fn test_spin_context() {
        let ctx = SpinContext::new(1.0)
            .at_spin(5, Some(10))
            .with_multiplier(3.0)
            .as_free();

        assert_eq!(ctx.spin_number, 5);
        assert_eq!(ctx.remaining_spins(), Some(5));
        assert!(!ctx.is_last_spin());
        assert!(ctx.is_free);

        let last = SpinContext::new(1.0).at_spin(10, Some(10));
        assert!(last.is_last_spin());
    }
}
