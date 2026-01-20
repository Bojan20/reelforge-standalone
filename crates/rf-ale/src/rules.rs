//! Rule System
//!
//! Rules define conditions and actions that drive layer transitions.
//! Each rule has:
//! - Conditions (signal comparisons, compound logic)
//! - Actions (step_up, step_down, set_level, hold, release, pulse)
//! - Transition profile
//! - Stability constraints (cooldown, hold duration)

use crate::context::LayerId;
use crate::signals::MetricSignals;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// Comparison operator for conditions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum ComparisonOp {
    /// Greater than
    Gt,
    /// Greater than or equal
    #[default]
    Gte,
    /// Less than
    Lt,
    /// Less than or equal
    Lte,
    /// Equal (with epsilon)
    Eq,
    /// Not equal
    Neq,
    /// Value changed from previous
    Changed,
    /// Value increased
    Increased,
    /// Value decreased
    Decreased,
    /// Value is in range [min, max]
    InRange,
    /// Value is outside range
    OutOfRange,
    /// Value crossed threshold (from below)
    CrossedUp,
    /// Value crossed threshold (from above)
    CrossedDown,
    /// Value is true (> 0.5)
    IsTrue,
    /// Value is false (<= 0.5)
    IsFalse,
}


/// Simple condition (signal comparison)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimpleCondition {
    /// Signal to compare
    pub signal: String,
    /// Comparison operator
    #[serde(default)]
    pub op: ComparisonOp,
    /// Threshold value
    #[serde(default)]
    pub value: f32,
    /// Second value for range comparisons
    #[serde(default)]
    pub value2: Option<f32>,
}

impl SimpleCondition {
    /// Create a new simple condition
    pub fn new(signal: &str, op: ComparisonOp, value: f32) -> Self {
        Self {
            signal: signal.to_string(),
            op,
            value,
            value2: None,
        }
    }

    /// Create a range condition
    pub fn in_range(signal: &str, min: f32, max: f32) -> Self {
        Self {
            signal: signal.to_string(),
            op: ComparisonOp::InRange,
            value: min,
            value2: Some(max),
        }
    }

    /// Evaluate the condition against current signals
    pub fn evaluate(&self, signals: &MetricSignals, prev_signals: Option<&MetricSignals>) -> bool {
        let current = signals.get(&self.signal);

        match self.op {
            ComparisonOp::Gt => current > self.value,
            ComparisonOp::Gte => current >= self.value,
            ComparisonOp::Lt => current < self.value,
            ComparisonOp::Lte => current <= self.value,
            ComparisonOp::Eq => (current - self.value).abs() < 0.001,
            ComparisonOp::Neq => (current - self.value).abs() >= 0.001,
            ComparisonOp::Changed => {
                if let Some(prev) = prev_signals {
                    (current - prev.get(&self.signal)).abs() > 0.001
                } else {
                    false
                }
            }
            ComparisonOp::Increased => {
                if let Some(prev) = prev_signals {
                    current > prev.get(&self.signal)
                } else {
                    false
                }
            }
            ComparisonOp::Decreased => {
                if let Some(prev) = prev_signals {
                    current < prev.get(&self.signal)
                } else {
                    false
                }
            }
            ComparisonOp::InRange => {
                let max = self.value2.unwrap_or(self.value);
                current >= self.value && current <= max
            }
            ComparisonOp::OutOfRange => {
                let max = self.value2.unwrap_or(self.value);
                current < self.value || current > max
            }
            ComparisonOp::CrossedUp => {
                if let Some(prev) = prev_signals {
                    let prev_val = prev.get(&self.signal);
                    prev_val < self.value && current >= self.value
                } else {
                    false
                }
            }
            ComparisonOp::CrossedDown => {
                if let Some(prev) = prev_signals {
                    let prev_val = prev.get(&self.signal);
                    prev_val > self.value && current <= self.value
                } else {
                    false
                }
            }
            ComparisonOp::IsTrue => current > 0.5,
            ComparisonOp::IsFalse => current <= 0.5,
        }
    }
}

/// Compound condition type
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CompoundType {
    /// All conditions must be true
    And,
    /// Any condition must be true
    Or,
    /// Condition must be false
    Not,
    /// Condition must be true for duration
    HeldFor,
    /// Conditions must occur in sequence
    Sequence,
}

/// Condition (can be simple or compound)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Condition {
    /// Simple signal comparison
    Simple(SimpleCondition),
    /// Compound condition
    Compound {
        /// Compound type
        #[serde(rename = "type")]
        compound_type: CompoundType,
        /// Sub-conditions
        conditions: Vec<Condition>,
        /// Duration for HeldFor (ms)
        #[serde(default)]
        duration_ms: Option<u32>,
    },
}

impl Condition {
    /// Create an AND compound condition
    pub fn and(conditions: Vec<Condition>) -> Self {
        Self::Compound {
            compound_type: CompoundType::And,
            conditions,
            duration_ms: None,
        }
    }

    /// Create an OR compound condition
    pub fn or(conditions: Vec<Condition>) -> Self {
        Self::Compound {
            compound_type: CompoundType::Or,
            conditions,
            duration_ms: None,
        }
    }

    /// Create a NOT compound condition
    pub fn negate(condition: Condition) -> Self {
        Self::Compound {
            compound_type: CompoundType::Not,
            conditions: vec![condition],
            duration_ms: None,
        }
    }

    /// Create a held_for compound condition
    pub fn held_for(condition: Condition, duration_ms: u32) -> Self {
        Self::Compound {
            compound_type: CompoundType::HeldFor,
            conditions: vec![condition],
            duration_ms: Some(duration_ms),
        }
    }

    /// Evaluate the condition
    pub fn evaluate(
        &self,
        signals: &MetricSignals,
        prev_signals: Option<&MetricSignals>,
        held_states: &mut HeldStates,
        current_time_ms: u64,
    ) -> bool {
        match self {
            Condition::Simple(simple) => simple.evaluate(signals, prev_signals),
            Condition::Compound {
                compound_type,
                conditions,
                duration_ms,
            } => match compound_type {
                CompoundType::And => conditions
                    .iter()
                    .all(|c| c.evaluate(signals, prev_signals, held_states, current_time_ms)),
                CompoundType::Or => conditions
                    .iter()
                    .any(|c| c.evaluate(signals, prev_signals, held_states, current_time_ms)),
                CompoundType::Not => {
                    !conditions
                        .first()
                        .is_some_and(|c| c.evaluate(signals, prev_signals, held_states, current_time_ms))
                }
                CompoundType::HeldFor => {
                    if let Some(first) = conditions.first() {
                        let is_true = first.evaluate(signals, prev_signals, held_states, current_time_ms);
                        let duration = duration_ms.unwrap_or(0);
                        held_states.check_held_for(self, is_true, duration, current_time_ms)
                    } else {
                        false
                    }
                }
                CompoundType::Sequence => {
                    // Sequence evaluation - each condition must fire in order
                    // Complex implementation - simplified here
                    conditions
                        .iter()
                        .all(|c| c.evaluate(signals, prev_signals, held_states, current_time_ms))
                }
            },
        }
    }
}

/// State tracking for HeldFor conditions
#[derive(Debug, Default)]
pub struct HeldStates {
    /// Map of condition hash to (start_time, was_true)
    states: std::collections::HashMap<u64, (u64, bool)>,
}

impl HeldStates {
    pub fn new() -> Self {
        Self::default()
    }

    /// Check if a condition has been held for the required duration
    fn check_held_for(
        &mut self,
        condition: &Condition,
        is_true: bool,
        duration_ms: u32,
        current_time_ms: u64,
    ) -> bool {
        let hash = self.hash_condition(condition);

        if is_true {
            match self.states.get(&hash) {
                Some((start_time, was_true)) if *was_true => {
                    // Check if we've been true long enough
                    current_time_ms.saturating_sub(*start_time) >= duration_ms as u64
                }
                _ => {
                    // Start tracking
                    self.states.insert(hash, (current_time_ms, true));
                    false
                }
            }
        } else {
            // Reset tracking
            self.states.insert(hash, (current_time_ms, false));
            false
        }
    }

    fn hash_condition(&self, condition: &Condition) -> u64 {
        // Simple pointer-based hash for condition identity
        condition as *const Condition as u64
    }

    /// Clear all held states
    pub fn clear(&mut self) {
        self.states.clear();
    }
}

/// Action type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum ActionType {
    /// Increase layer level by steps
    #[default]
    StepUp,
    /// Decrease layer level by steps
    StepDown,
    /// Set layer to specific level
    SetLevel,
    /// Hold current level (prevent changes)
    Hold,
    /// Release hold
    Release,
    /// Momentary pulse to level then return
    Pulse,
}


/// Rule action
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Action {
    /// Action type
    #[serde(rename = "type")]
    pub action_type: ActionType,
    /// Number of steps for step_up/step_down
    #[serde(default = "default_steps")]
    pub steps: u8,
    /// Target level for set_level
    #[serde(default)]
    pub level: Option<LayerId>,
    /// Maximum level for step_up
    #[serde(default)]
    pub max_level: Option<LayerId>,
    /// Minimum level for step_down
    #[serde(default)]
    pub min_level: Option<LayerId>,
    /// Whether to allow skipping levels
    #[serde(default)]
    pub allow_skip: bool,
    /// Hold duration (ms) for hold/pulse
    #[serde(default)]
    pub hold_duration_ms: Option<u32>,
    /// Return level for pulse
    #[serde(default)]
    pub return_level: Option<LayerId>,
}

fn default_steps() -> u8 {
    1
}

impl Default for Action {
    fn default() -> Self {
        Self {
            action_type: ActionType::StepUp,
            steps: 1,
            level: None,
            max_level: None,
            min_level: None,
            allow_skip: false,
            hold_duration_ms: None,
            return_level: None,
        }
    }
}

impl Action {
    /// Create a step_up action
    pub fn step_up(steps: u8) -> Self {
        Self {
            action_type: ActionType::StepUp,
            steps,
            ..Default::default()
        }
    }

    /// Create a step_down action
    pub fn step_down(steps: u8) -> Self {
        Self {
            action_type: ActionType::StepDown,
            steps,
            ..Default::default()
        }
    }

    /// Create a set_level action
    pub fn set_level(level: LayerId) -> Self {
        Self {
            action_type: ActionType::SetLevel,
            level: Some(level),
            ..Default::default()
        }
    }

    /// Create a hold action
    pub fn hold(duration_ms: u32) -> Self {
        Self {
            action_type: ActionType::Hold,
            hold_duration_ms: Some(duration_ms),
            ..Default::default()
        }
    }

    /// Create a release action
    pub fn release() -> Self {
        Self {
            action_type: ActionType::Release,
            ..Default::default()
        }
    }

    /// Create a pulse action
    pub fn pulse(level: LayerId, duration_ms: u32, return_level: LayerId) -> Self {
        Self {
            action_type: ActionType::Pulse,
            level: Some(level),
            hold_duration_ms: Some(duration_ms),
            return_level: Some(return_level),
            ..Default::default()
        }
    }

    /// Apply action to current level
    pub fn apply(&self, current_level: LayerId, min: LayerId, max: LayerId) -> LayerId {
        match self.action_type {
            ActionType::StepUp => {
                let target = current_level.saturating_add(self.steps);
                let cap = self.max_level.unwrap_or(max);
                target.min(cap).min(max)
            }
            ActionType::StepDown => {
                let target = current_level.saturating_sub(self.steps);
                let floor = self.min_level.unwrap_or(min);
                target.max(floor).max(min)
            }
            ActionType::SetLevel => self.level.unwrap_or(current_level).clamp(min, max),
            ActionType::Hold | ActionType::Release => current_level,
            ActionType::Pulse => self.level.unwrap_or(current_level).clamp(min, max),
        }
    }
}

/// Side effect when rule fires
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SideEffect {
    /// Trigger a stinger audio
    #[serde(default)]
    pub stinger: Option<String>,
    /// Stinger volume
    #[serde(default = "default_stinger_volume")]
    pub stinger_volume: f32,
    /// Emit an event
    #[serde(default)]
    pub emit_event: Option<String>,
    /// Update momentum by this delta
    #[serde(default)]
    pub momentum_delta: Option<f32>,
}

fn default_stinger_volume() -> f32 {
    0.7
}

impl Default for SideEffect {
    fn default() -> Self {
        Self {
            stinger: None,
            stinger_volume: 0.7,
            emit_event: None,
            momentum_delta: None,
        }
    }
}

/// Complete rule definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    /// Rule identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Whether rule is enabled
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    /// Priority (higher = evaluated first)
    #[serde(default = "default_priority")]
    pub priority: i32,
    /// Context IDs where this rule is active
    #[serde(default)]
    pub contexts: HashSet<String>,
    /// Condition to trigger the rule
    pub condition: Condition,
    /// Action to perform when triggered
    pub action: Action,
    /// Transition profile name
    #[serde(default)]
    pub transition: Option<String>,
    /// Cooldown after firing (ms)
    #[serde(default)]
    pub cooldown_ms: u32,
    /// Hold duration after firing (ms)
    #[serde(default)]
    pub hold_ms: u32,
    /// Whether rule requires hold to be expired
    #[serde(default)]
    pub requires_hold_expired: bool,
    /// Side effects
    #[serde(default)]
    pub side_effects: SideEffect,
}

fn default_enabled() -> bool {
    true
}

fn default_priority() -> i32 {
    100
}

impl Rule {
    /// Create a new rule
    pub fn new(id: &str, name: &str, condition: Condition, action: Action) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            enabled: true,
            priority: 100,
            contexts: HashSet::new(),
            condition,
            action,
            transition: None,
            cooldown_ms: 0,
            hold_ms: 0,
            requires_hold_expired: false,
            side_effects: SideEffect::default(),
        }
    }

    /// Add context restriction
    pub fn for_context(mut self, context: &str) -> Self {
        self.contexts.insert(context.to_string());
        self
    }

    /// Set transition profile
    pub fn with_transition(mut self, transition: &str) -> Self {
        self.transition = Some(transition.to_string());
        self
    }

    /// Set cooldown
    pub fn with_cooldown(mut self, cooldown_ms: u32) -> Self {
        self.cooldown_ms = cooldown_ms;
        self
    }

    /// Set hold
    pub fn with_hold(mut self, hold_ms: u32) -> Self {
        self.hold_ms = hold_ms;
        self
    }

    /// Set priority
    pub fn with_priority(mut self, priority: i32) -> Self {
        self.priority = priority;
        self
    }

    /// Check if rule applies to context
    pub fn applies_to_context(&self, context_id: &str) -> bool {
        self.contexts.is_empty() || self.contexts.contains(context_id)
    }

    /// Evaluate the rule
    pub fn evaluate(
        &self,
        context_id: &str,
        signals: &MetricSignals,
        prev_signals: Option<&MetricSignals>,
        held_states: &mut HeldStates,
        current_time_ms: u64,
    ) -> bool {
        if !self.enabled {
            return false;
        }
        if !self.applies_to_context(context_id) {
            return false;
        }
        self.condition
            .evaluate(signals, prev_signals, held_states, current_time_ms)
    }
}

/// Rule registry
#[derive(Debug, Clone, Default)]
pub struct RuleRegistry {
    rules: Vec<Rule>,
}

impl RuleRegistry {
    pub fn new() -> Self {
        Self { rules: Vec::new() }
    }

    /// Add a rule
    pub fn add(&mut self, rule: Rule) {
        self.rules.push(rule);
        // Sort by priority (descending)
        self.rules.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    /// Get all rules for a context
    pub fn for_context(&self, context_id: &str) -> impl Iterator<Item = &Rule> {
        self.rules
            .iter()
            .filter(move |r| r.applies_to_context(context_id))
    }

    /// Find first matching rule
    pub fn find_match(
        &self,
        context_id: &str,
        signals: &MetricSignals,
        prev_signals: Option<&MetricSignals>,
        held_states: &mut HeldStates,
        current_time_ms: u64,
    ) -> Option<&Rule> {
        self.rules.iter().find(|r| {
            r.evaluate(
                context_id,
                signals,
                prev_signals,
                held_states,
                current_time_ms,
            )
        })
    }

    /// Number of rules
    pub fn len(&self) -> usize {
        self.rules.len()
    }

    /// Check if registry is empty
    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }

    /// Get all rules
    pub fn all(&self) -> &[Rule] {
        &self.rules
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_condition_gt() {
        let cond = SimpleCondition::new("winTier", ComparisonOp::Gt, 2.0);
        let mut signals = MetricSignals::new();

        signals.set("winTier", 1.0);
        assert!(!cond.evaluate(&signals, None));

        signals.set("winTier", 3.0);
        assert!(cond.evaluate(&signals, None));
    }

    #[test]
    fn test_simple_condition_in_range() {
        let cond = SimpleCondition::in_range("winTier", 2.0, 4.0);
        let mut signals = MetricSignals::new();

        signals.set("winTier", 1.0);
        assert!(!cond.evaluate(&signals, None));

        signals.set("winTier", 3.0);
        assert!(cond.evaluate(&signals, None));

        signals.set("winTier", 5.0);
        assert!(!cond.evaluate(&signals, None));
    }

    #[test]
    fn test_compound_condition_and() {
        let cond = Condition::and(vec![
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 3.0)),
            Condition::Simple(SimpleCondition::new("momentum", ComparisonOp::Gte, 0.5)),
        ]);

        let mut signals = MetricSignals::new();
        let mut held_states = HeldStates::new();

        signals.set("winTier", 4.0);
        signals.set("momentum", 0.3);
        assert!(!cond.evaluate(&signals, None, &mut held_states, 0));

        signals.set("momentum", 0.7);
        assert!(cond.evaluate(&signals, None, &mut held_states, 0));
    }

    #[test]
    fn test_compound_condition_or() {
        let cond = Condition::or(vec![
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 4.0)),
            Condition::Simple(SimpleCondition::new("consecutiveWins", ComparisonOp::Gte, 3.0)),
        ]);

        let mut signals = MetricSignals::new();
        let mut held_states = HeldStates::new();

        signals.set("winTier", 2.0);
        signals.set("consecutiveWins", 1.0);
        assert!(!cond.evaluate(&signals, None, &mut held_states, 0));

        signals.set("winTier", 5.0);
        assert!(cond.evaluate(&signals, None, &mut held_states, 0));

        signals.set("winTier", 2.0);
        signals.set("consecutiveWins", 4.0);
        assert!(cond.evaluate(&signals, None, &mut held_states, 0));
    }

    #[test]
    fn test_action_step_up() {
        let action = Action::step_up(1);
        assert_eq!(action.apply(2, 0, 4), 3);
        assert_eq!(action.apply(4, 0, 4), 4); // Capped at max
    }

    #[test]
    fn test_action_step_down() {
        let action = Action::step_down(2);
        assert_eq!(action.apply(3, 0, 4), 1);
        assert_eq!(action.apply(1, 0, 4), 0); // Floored at min
    }

    #[test]
    fn test_rule_context_filter() {
        let rule = Rule::new(
            "test",
            "Test Rule",
            Condition::Simple(SimpleCondition::new("winTier", ComparisonOp::Gte, 3.0)),
            Action::step_up(1),
        )
        .for_context("FREESPINS");

        assert!(rule.applies_to_context("FREESPINS"));
        assert!(!rule.applies_to_context("BASE"));
    }

    #[test]
    fn test_rule_registry_priority() {
        let mut registry = RuleRegistry::new();

        registry.add(
            Rule::new(
                "low",
                "Low Priority",
                Condition::Simple(SimpleCondition::new("a", ComparisonOp::Gte, 0.0)),
                Action::step_up(1),
            )
            .with_priority(50),
        );

        registry.add(
            Rule::new(
                "high",
                "High Priority",
                Condition::Simple(SimpleCondition::new("a", ComparisonOp::Gte, 0.0)),
                Action::step_up(1),
            )
            .with_priority(200),
        );

        // High priority should be first
        assert_eq!(registry.all()[0].id, "high");
        assert_eq!(registry.all()[1].id, "low");
    }
}
