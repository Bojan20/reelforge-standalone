//! Feature types and identifiers

use serde::{Deserialize, Serialize};

/// Unique feature identifier
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FeatureId(pub String);

impl FeatureId {
    /// Create a new feature ID
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    /// Get the ID string
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for FeatureId {
    fn from(s: &str) -> Self {
        Self::new(s)
    }
}

impl From<String> for FeatureId {
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl std::fmt::Display for FeatureId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Feature category for grouping
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeatureCategory {
    /// Free spins feature
    FreeSpins,
    /// Cascade/tumble mechanics
    Cascade,
    /// Hold and win / respins
    HoldAndWin,
    /// Jackpot features
    Jackpot,
    /// Bonus games
    Bonus,
    /// Gamble/risk feature
    Gamble,
    /// Multiplier mechanics
    Multiplier,
    /// Wild-related features
    Wild,
    /// Other/custom features
    Other,
}

impl FeatureCategory {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::FreeSpins => "Free Spins",
            Self::Cascade => "Cascades",
            Self::HoldAndWin => "Hold & Win",
            Self::Jackpot => "Jackpot",
            Self::Bonus => "Bonus",
            Self::Gamble => "Gamble",
            Self::Multiplier => "Multiplier",
            Self::Wild => "Wild",
            Self::Other => "Other",
        }
    }
}

/// Feature configuration from GDD
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FeatureConfig {
    /// Configuration parameters
    #[serde(default)]
    pub params: std::collections::HashMap<String, serde_json::Value>,
}

impl FeatureConfig {
    /// Create empty config
    pub fn new() -> Self {
        Self::default()
    }

    /// Get a parameter value
    pub fn get<T: serde::de::DeserializeOwned>(&self, key: &str) -> Option<T> {
        self.params
            .get(key)
            .and_then(|v| serde_json::from_value(v.clone()).ok())
    }

    /// Get a parameter with default
    pub fn get_or<T: serde::de::DeserializeOwned>(&self, key: &str, default: T) -> T {
        self.get(key).unwrap_or(default)
    }

    /// Set a parameter
    pub fn set<T: Serialize>(&mut self, key: impl Into<String>, value: T) {
        if let Ok(v) = serde_json::to_value(value) {
            self.params.insert(key.into(), v);
        }
    }

    /// Check if a parameter exists
    pub fn has(&self, key: &str) -> bool {
        self.params.contains_key(key)
    }
}

/// Result of processing a spin within a feature
#[derive(Debug, Clone, Default)]
pub struct FeatureResult {
    /// Continue the feature (more steps remaining)?
    pub continue_feature: bool,

    /// Win contribution from this step
    pub win_amount: f64,

    /// Multiplier to apply
    pub multiplier: f64,

    /// Trigger another feature?
    pub trigger_feature: Option<FeatureId>,

    /// Additional data
    pub data: std::collections::HashMap<String, serde_json::Value>,
}

impl FeatureResult {
    /// Create a result for inactive feature (no-op)
    pub fn inactive() -> Self {
        Self {
            continue_feature: false,
            win_amount: 0.0,
            multiplier: 1.0,
            trigger_feature: None,
            data: Default::default(),
        }
    }

    /// Create a result indicating feature should continue
    pub fn continue_with(win: f64) -> Self {
        Self {
            continue_feature: true,
            win_amount: win,
            multiplier: 1.0,
            trigger_feature: None,
            data: Default::default(),
        }
    }

    /// Create a result indicating feature is complete
    pub fn complete(win: f64) -> Self {
        Self {
            continue_feature: false,
            win_amount: win,
            multiplier: 1.0,
            trigger_feature: None,
            data: Default::default(),
        }
    }

    /// Check if feature continues
    pub fn continues(&self) -> bool {
        self.continue_feature
    }

    /// Builder: set multiplier
    pub fn with_multiplier(mut self, mult: f64) -> Self {
        self.multiplier = mult;
        self
    }

    /// Builder: add data
    pub fn with_data(mut self, key: &str, value: serde_json::Value) -> Self {
        self.data.insert(key.to_string(), value);
        self
    }

    /// Builder: trigger another feature
    pub fn triggering(mut self, feature: impl Into<FeatureId>) -> Self {
        self.trigger_feature = Some(feature.into());
        self
    }
}

/// Feature state enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum FeatureState {
    /// Feature is inactive
    #[default]
    Inactive,
    /// Feature is triggered, waiting to start
    Triggered,
    /// Feature is active (in progress)
    Active,
    /// Feature is completing (outro)
    Completing,
}

impl FeatureState {
    /// Check if feature is currently running
    pub fn is_active(&self) -> bool {
        matches!(self, Self::Triggered | Self::Active | Self::Completing)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feature_id() {
        let id = FeatureId::new("free_spins");
        assert_eq!(id.as_str(), "free_spins");

        let from_str: FeatureId = "cascades".into();
        assert_eq!(from_str.as_str(), "cascades");
    }

    #[test]
    fn test_feature_config() {
        let mut config = FeatureConfig::new();
        config.set("spins", 10);
        config.set("multiplier", 2.5);

        assert_eq!(config.get::<i32>("spins"), Some(10));
        assert_eq!(config.get::<f64>("multiplier"), Some(2.5));
        assert_eq!(config.get_or("missing", 5), 5);
    }

    #[test]
    fn test_feature_result() {
        let result = FeatureResult::continue_with(100.0)
            .with_multiplier(2.0)
            .triggering("bonus");

        assert!(result.continue_feature);
        assert!((result.win_amount - 100.0).abs() < 0.001);
        assert!((result.multiplier - 2.0).abs() < 0.001);
        assert!(result.trigger_feature.is_some());
    }
}
