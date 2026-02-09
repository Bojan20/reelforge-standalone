//! Layer 3: Rule-Based Reconstruction
//!
//! Derives STAGES using heuristic rules when no explicit events or snapshots exist.
//! Analyzes timing patterns, value changes, and behavioral signatures.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::adapter::AdapterError;
use rf_stage::event::StageEvent;
use rf_stage::stage::Stage;
use rf_stage::taxonomy::{BigWinTier, FeatureType};

/// Rule definition for stage derivation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DerivationRule {
    /// Rule identifier
    pub id: String,

    /// Rule description
    pub description: String,

    /// Conditions that must be met
    pub conditions: Vec<RuleCondition>,

    /// Stage to emit when conditions are met
    pub emit_stage: String,

    /// Priority (higher = checked first)
    pub priority: i32,

    /// Is this rule enabled
    pub enabled: bool,
}

/// Condition for a derivation rule
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum RuleCondition {
    /// Field equals value
    FieldEquals { path: String, value: Value },

    /// Field changed from previous
    FieldChanged { path: String },

    /// Field increased
    FieldIncreased { path: String },

    /// Field decreased
    FieldDecreased { path: String },

    /// Field matches pattern
    FieldMatches { path: String, pattern: String },

    /// Field is present
    FieldPresent { path: String },

    /// Field is absent
    FieldAbsent { path: String },

    /// Time elapsed since last event
    TimeElapsed { min_ms: f64, max_ms: Option<f64> },

    /// Sequence detected (multiple conditions in order)
    Sequence { conditions: Vec<RuleCondition> },

    /// Any of the conditions (OR)
    Any { conditions: Vec<RuleCondition> },

    /// All of the conditions (AND)
    All { conditions: Vec<RuleCondition> },

    /// Negation
    Not { condition: Box<RuleCondition> },
}

/// Rule engine for stage derivation
#[derive(Debug, Clone)]
pub struct RuleEngine {
    /// Active rules
    rules: Vec<DerivationRule>,

    /// Previous event data for comparison
    previous_data: Option<Value>,

    /// Last event timestamp
    last_timestamp: f64,

    /// Detected stages
    detected_stages: Vec<StageEvent>,
}

impl Default for RuleEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl RuleEngine {
    /// Create new rule engine with default rules
    pub fn new() -> Self {
        Self {
            rules: default_rules(),
            previous_data: None,
            last_timestamp: 0.0,
            detected_stages: Vec::new(),
        }
    }

    /// Create rule engine with custom rules
    pub fn with_rules(rules: Vec<DerivationRule>) -> Self {
        let mut engine = Self::new();
        engine.rules = rules;
        engine.sort_rules();
        engine
    }

    /// Add a rule
    pub fn add_rule(&mut self, rule: DerivationRule) {
        self.rules.push(rule);
        self.sort_rules();
    }

    /// Sort rules by priority
    fn sort_rules(&mut self) {
        self.rules.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    /// Process a data point and derive stages
    pub fn process(
        &mut self,
        data: &Value,
        timestamp_ms: f64,
    ) -> Result<Vec<StageEvent>, AdapterError> {
        let mut events = Vec::new();

        for rule in &self.rules {
            if !rule.enabled {
                continue;
            }

            if self.evaluate_conditions(&rule.conditions, data, timestamp_ms) {
                if let Some(stage) = self.create_stage(&rule.emit_stage, data, timestamp_ms) {
                    events.push(stage);
                }
            }
        }

        self.previous_data = Some(data.clone());
        self.last_timestamp = timestamp_ms;
        self.detected_stages.extend(events.clone());

        Ok(events)
    }

    /// Evaluate rule conditions
    fn evaluate_conditions(
        &self,
        conditions: &[RuleCondition],
        data: &Value,
        timestamp_ms: f64,
    ) -> bool {
        conditions
            .iter()
            .all(|c| self.evaluate_condition(c, data, timestamp_ms))
    }

    /// Evaluate a single condition
    fn evaluate_condition(
        &self,
        condition: &RuleCondition,
        data: &Value,
        timestamp_ms: f64,
    ) -> bool {
        match condition {
            RuleCondition::FieldEquals { path, value } => get_json_value(data, path)
                .map(|v| v == value)
                .unwrap_or(false),

            RuleCondition::FieldChanged { path } => {
                if let Some(prev) = &self.previous_data {
                    let prev_val = get_json_value(prev, path);
                    let curr_val = get_json_value(data, path);
                    prev_val != curr_val
                } else {
                    false
                }
            }

            RuleCondition::FieldIncreased { path } => {
                if let Some(prev) = &self.previous_data {
                    let prev_val = get_json_value(prev, path).and_then(|v| v.as_f64());
                    let curr_val = get_json_value(data, path).and_then(|v| v.as_f64());
                    match (prev_val, curr_val) {
                        (Some(p), Some(c)) => c > p,
                        _ => false,
                    }
                } else {
                    false
                }
            }

            RuleCondition::FieldDecreased { path } => {
                if let Some(prev) = &self.previous_data {
                    let prev_val = get_json_value(prev, path).and_then(|v| v.as_f64());
                    let curr_val = get_json_value(data, path).and_then(|v| v.as_f64());
                    match (prev_val, curr_val) {
                        (Some(p), Some(c)) => c < p,
                        _ => false,
                    }
                } else {
                    false
                }
            }

            RuleCondition::FieldMatches { path, pattern } => {
                if let Some(val) = get_json_value(data, path).and_then(|v| v.as_str()) {
                    regex::Regex::new(pattern)
                        .map(|re| re.is_match(val))
                        .unwrap_or(false)
                } else {
                    false
                }
            }

            RuleCondition::FieldPresent { path } => get_json_value(data, path).is_some(),

            RuleCondition::FieldAbsent { path } => get_json_value(data, path).is_none(),

            RuleCondition::TimeElapsed { min_ms, max_ms } => {
                let elapsed = timestamp_ms - self.last_timestamp;
                elapsed >= *min_ms && max_ms.map(|m| elapsed <= m).unwrap_or(true)
            }

            RuleCondition::Sequence { conditions } => {
                // Sequence requires all conditions in order
                // For now, simplified to AND
                conditions
                    .iter()
                    .all(|c| self.evaluate_condition(c, data, timestamp_ms))
            }

            RuleCondition::Any { conditions } => conditions
                .iter()
                .any(|c| self.evaluate_condition(c, data, timestamp_ms)),

            RuleCondition::All { conditions } => conditions
                .iter()
                .all(|c| self.evaluate_condition(c, data, timestamp_ms)),

            RuleCondition::Not { condition } => {
                !self.evaluate_condition(condition, data, timestamp_ms)
            }
        }
    }

    /// Create stage from rule emit string
    fn create_stage(
        &self,
        emit_stage: &str,
        data: &Value,
        timestamp_ms: f64,
    ) -> Option<StageEvent> {
        let stage = match emit_stage {
            "SpinStart" => Stage::SpinStart,
            "SpinEnd" => Stage::SpinEnd,
            "IdleStart" => Stage::IdleStart,

            s if s.starts_with("ReelStop") => {
                let reel_index = extract_param::<u8>(s, "reel_index").unwrap_or(0);
                Stage::ReelStop {
                    reel_index,
                    symbols: vec![],
                }
            }

            s if s.starts_with("AnticipationOn") => {
                let reel_index = extract_param::<u8>(s, "reel_index").unwrap_or(0);
                Stage::AnticipationOn {
                    reel_index,
                    reason: None,
                }
            }

            "AnticipationOff" => Stage::AnticipationOff { reel_index: 0 },

            "WinPresent" => {
                let win_amount = get_json_value(data, "win_amount")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                Stage::WinPresent {
                    win_amount,
                    line_count: 0,
                }
            }

            "BigWinTier" => {
                let tier = BigWinTier::Win;
                let amount = get_json_value(data, "win_amount")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                Stage::BigWinTier { tier, amount }
            }

            s if s.starts_with("FeatureEnter") => {
                let feature_str = extract_param_str(s, "feature_type").unwrap_or("custom");
                let feature_type = match feature_str {
                    "FreeSpins" => FeatureType::FreeSpins,
                    "PickBonus" => FeatureType::PickBonus,
                    "Respin" => FeatureType::Respin,
                    "Cascade" => FeatureType::Cascade,
                    "WheelBonus" => FeatureType::WheelBonus,
                    _ => FeatureType::Custom(0),
                };
                Stage::FeatureEnter {
                    feature_type,
                    total_steps: None,
                    multiplier: 1.0,
                }
            }

            "FeatureExit" => Stage::FeatureExit { total_win: 0.0 },

            "RollupStart" => {
                let amount = get_json_value(data, "win_amount")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                Stage::RollupStart {
                    target_amount: amount,
                    start_amount: 0.0,
                }
            }

            "RollupEnd" => Stage::RollupEnd { final_amount: 0.0 },

            "GambleStart" => Stage::GambleStart { stake_amount: 0.0 },

            "GambleEnd" => Stage::GambleEnd {
                collected_amount: 0.0,
            },

            _ => return None,
        };

        Some(StageEvent::new(stage, timestamp_ms))
    }

    /// Reset engine state
    pub fn reset(&mut self) {
        self.previous_data = None;
        self.last_timestamp = 0.0;
        self.detected_stages.clear();
    }

    /// Get all detected stages
    pub fn get_detected_stages(&self) -> &[StageEvent] {
        &self.detected_stages
    }
}

/// Create default derivation rules
fn default_rules() -> Vec<DerivationRule> {
    vec![
        // Spin start: balance decreased
        DerivationRule {
            id: "spin_start_balance".to_string(),
            description: "Detect spin start from balance decrease".to_string(),
            conditions: vec![RuleCondition::FieldDecreased {
                path: "balance".to_string(),
            }],
            emit_stage: "SpinStart".to_string(),
            priority: 100,
            enabled: true,
        },
        // Spin end: reels stopped + win evaluated
        DerivationRule {
            id: "spin_end_reels".to_string(),
            description: "Detect spin end when all reels stopped".to_string(),
            conditions: vec![
                RuleCondition::FieldEquals {
                    path: "state".to_string(),
                    value: Value::String("idle".to_string()),
                },
                RuleCondition::FieldChanged {
                    path: "state".to_string(),
                },
            ],
            emit_stage: "SpinEnd".to_string(),
            priority: 90,
            enabled: true,
        },
        // Win present: win amount increased from 0
        DerivationRule {
            id: "win_present".to_string(),
            description: "Detect win when win amount increases".to_string(),
            conditions: vec![RuleCondition::FieldIncreased {
                path: "win_amount".to_string(),
            }],
            emit_stage: "WinPresent".to_string(),
            priority: 80,
            enabled: true,
        },
        // Big win: win amount exceeds threshold
        DerivationRule {
            id: "big_win_detect".to_string(),
            description: "Detect big win tier".to_string(),
            conditions: vec![
                RuleCondition::FieldPresent {
                    path: "big_win_tier".to_string(),
                },
                RuleCondition::FieldChanged {
                    path: "big_win_tier".to_string(),
                },
            ],
            emit_stage: "BigWinTier".to_string(),
            priority: 85,
            enabled: true,
        },
        // Feature enter
        DerivationRule {
            id: "feature_enter".to_string(),
            description: "Detect feature entry".to_string(),
            conditions: vec![
                RuleCondition::FieldPresent {
                    path: "feature".to_string(),
                },
                RuleCondition::FieldChanged {
                    path: "feature".to_string(),
                },
            ],
            emit_stage: "FeatureEnter".to_string(),
            priority: 70,
            enabled: true,
        },
    ]
}

// Helper functions

fn get_json_value<'a>(json: &'a Value, path: &str) -> Option<&'a Value> {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = json;

    for part in parts {
        current = current.get(part)?;
    }

    Some(current)
}

fn extract_param<T: std::str::FromStr>(s: &str, param: &str) -> Option<T> {
    let pattern = format!("{}: ", param);
    if let Some(start) = s.find(&pattern) {
        let value_start = start + pattern.len();
        let rest = &s[value_start..];
        let end = rest
            .find(|c: char| !c.is_numeric() && c != '.' && c != '-')
            .unwrap_or(rest.len());
        rest[..end].parse().ok()
    } else {
        None
    }
}

fn extract_param_str<'a>(s: &'a str, param: &str) -> Option<&'a str> {
    let pattern = format!("{}: ", param);
    if let Some(start) = s.find(&pattern) {
        let value_start = start + pattern.len();
        let rest = &s[value_start..];
        let end = rest.find([',', '}', ' ']).unwrap_or(rest.len());
        Some(&rest[..end])
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_rule_engine_spin_start() {
        let mut engine = RuleEngine::new();

        // First data point
        let data1 = json!({
            "balance": 1000.0,
            "state": "idle"
        });
        engine.process(&data1, 0.0).unwrap();

        // Balance decreased = spin start
        let data2 = json!({
            "balance": 990.0,
            "state": "spinning"
        });
        let events = engine.process(&data2, 100.0).unwrap();

        assert!(events.iter().any(|e| matches!(e.stage, Stage::SpinStart)));
    }

    #[test]
    fn test_rule_condition_field_equals() {
        let engine = RuleEngine::new();
        let data = json!({ "state": "idle" });

        let condition = RuleCondition::FieldEquals {
            path: "state".to_string(),
            value: Value::String("idle".to_string()),
        };

        assert!(engine.evaluate_condition(&condition, &data, 0.0));
    }

    #[test]
    fn test_rule_condition_any() {
        let engine = RuleEngine::new();
        let data = json!({ "state": "spinning" });

        let condition = RuleCondition::Any {
            conditions: vec![
                RuleCondition::FieldEquals {
                    path: "state".to_string(),
                    value: Value::String("idle".to_string()),
                },
                RuleCondition::FieldEquals {
                    path: "state".to_string(),
                    value: Value::String("spinning".to_string()),
                },
            ],
        };

        assert!(engine.evaluate_condition(&condition, &data, 0.0));
    }
}
