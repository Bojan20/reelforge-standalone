//! Adapter Configuration — TOML-based config for mapping engine events to STAGES

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::adapter::{AdapterError, IngestLayer};

/// Complete adapter configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdapterConfig {
    /// Unique adapter ID
    pub adapter_id: String,

    /// Company name
    pub company_name: String,

    /// Engine/platform name
    pub engine_name: String,

    /// Config version
    #[serde(default = "default_version")]
    pub version: String,

    /// Supported ingest layers
    #[serde(default)]
    pub layers: Vec<IngestLayer>,

    /// Event name to Stage mapping
    #[serde(default)]
    pub event_mapping: HashMap<String, String>,

    /// JSONPath expressions for payload extraction
    #[serde(default)]
    pub payload_paths: PayloadPaths,

    /// Snapshot paths for diff derivation (Layer 2)
    #[serde(default)]
    pub snapshot_paths: SnapshotPaths,

    /// Big win threshold configuration
    #[serde(default)]
    pub bigwin_thresholds: BigWinThresholds,

    /// Custom metadata
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
}

fn default_version() -> String {
    "1.0".to_string()
}

impl Default for AdapterConfig {
    fn default() -> Self {
        Self {
            adapter_id: "generic".to_string(),
            company_name: "Generic".to_string(),
            engine_name: "Unknown".to_string(),
            version: default_version(),
            layers: vec![IngestLayer::DirectEvent],
            event_mapping: HashMap::new(),
            payload_paths: PayloadPaths::default(),
            snapshot_paths: SnapshotPaths::default(),
            bigwin_thresholds: BigWinThresholds::default(),
            metadata: HashMap::new(),
        }
    }
}

impl AdapterConfig {
    /// Create a new config with required fields
    pub fn new(adapter_id: &str, company_name: &str, engine_name: &str) -> Self {
        Self {
            adapter_id: adapter_id.to_string(),
            company_name: company_name.to_string(),
            engine_name: engine_name.to_string(),
            ..Default::default()
        }
    }

    /// Load from TOML string
    pub fn from_toml(toml_str: &str) -> Result<Self, AdapterError> {
        toml::from_str(toml_str).map_err(|e| AdapterError::ConfigError(e.to_string()))
    }

    /// Save to TOML string
    pub fn to_toml(&self) -> Result<String, AdapterError> {
        toml::to_string_pretty(self).map_err(|e| AdapterError::ConfigError(e.to_string()))
    }

    /// Add an event mapping
    pub fn map_event(&mut self, engine_event: &str, stage: &str) -> &mut Self {
        self.event_mapping
            .insert(engine_event.to_string(), stage.to_string());
        self
    }

    /// Get stage for an event name
    pub fn get_stage(&self, event_name: &str) -> Option<&str> {
        self.event_mapping.get(event_name).map(|s| s.as_str())
    }

    /// Validate the configuration
    pub fn validate(&self) -> Result<(), AdapterError> {
        if self.adapter_id.is_empty() {
            return Err(AdapterError::ConfigError(
                "adapter_id cannot be empty".to_string(),
            ));
        }
        if self.company_name.is_empty() {
            return Err(AdapterError::ConfigError(
                "company_name cannot be empty".to_string(),
            ));
        }
        if self.layers.is_empty() {
            return Err(AdapterError::ConfigError(
                "at least one ingest layer must be specified".to_string(),
            ));
        }
        Ok(())
    }
}

/// JSONPath expressions for extracting payload data
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PayloadPaths {
    /// Path to events array
    #[serde(default)]
    pub events_path: Option<String>,

    /// Path to event name field
    #[serde(default)]
    pub event_name_path: Option<String>,

    /// Path to event timestamp
    #[serde(default)]
    pub timestamp_path: Option<String>,

    /// Path to win amount
    #[serde(default)]
    pub win_amount_path: Option<String>,

    /// Path to bet amount
    #[serde(default)]
    pub bet_amount_path: Option<String>,

    /// Path to reel data
    #[serde(default)]
    pub reel_data_path: Option<String>,

    /// Path to feature data
    #[serde(default)]
    pub feature_path: Option<String>,

    /// Path to symbol data
    #[serde(default)]
    pub symbol_path: Option<String>,
}

/// Paths for snapshot diff derivation
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SnapshotPaths {
    /// Path to reels state
    #[serde(default)]
    pub reels_path: Option<String>,

    /// Path to total win
    #[serde(default)]
    pub win_path: Option<String>,

    /// Path to feature active flag
    #[serde(default)]
    pub feature_active_path: Option<String>,

    /// Path to balance
    #[serde(default)]
    pub balance_path: Option<String>,
}

/// Big win tier thresholds (win-to-bet ratios)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BigWinThresholds {
    pub win: f64,
    pub big_win: f64,
    pub mega_win: f64,
    pub epic_win: f64,
    pub ultra_win: f64,
}

impl Default for BigWinThresholds {
    fn default() -> Self {
        Self {
            win: 10.0,
            big_win: 15.0,
            mega_win: 25.0,
            epic_win: 50.0,
            ultra_win: 100.0,
        }
    }
}

// Serde support for IngestLayer
impl Serialize for IngestLayer {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let s = match self {
            IngestLayer::DirectEvent => "direct_event",
            IngestLayer::SnapshotDiff => "snapshot_diff",
            IngestLayer::RuleBased => "rule_based",
        };
        serializer.serialize_str(s)
    }
}

impl<'de> Deserialize<'de> for IngestLayer {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        match s.as_str() {
            "direct_event" => Ok(IngestLayer::DirectEvent),
            "snapshot_diff" => Ok(IngestLayer::SnapshotDiff),
            "rule_based" => Ok(IngestLayer::RuleBased),
            _ => Err(serde::de::Error::custom(format!(
                "unknown ingest layer: {}",
                s
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_creation() {
        let mut config = AdapterConfig::new("test-adapter", "Test Company", "Test Engine");
        config.map_event("spin_start", "SpinStart");
        config.map_event("reel_stop_0", "ReelStop { reel_index: 0 }");

        assert_eq!(config.adapter_id, "test-adapter");
        assert_eq!(config.get_stage("spin_start"), Some("SpinStart"));
    }

    #[test]
    fn test_config_toml_roundtrip() {
        let mut config = AdapterConfig::new("igt-avp", "IGT", "AVP");
        config.map_event("cmd_spin", "SpinStart");
        config.layers = vec![IngestLayer::DirectEvent, IngestLayer::SnapshotDiff];

        let toml = config.to_toml().unwrap();
        let parsed = AdapterConfig::from_toml(&toml).unwrap();

        assert_eq!(parsed.adapter_id, config.adapter_id);
        assert_eq!(parsed.layers, config.layers);
    }

    #[test]
    fn test_config_validation() {
        let mut config = AdapterConfig::default();
        config.adapter_id = "".to_string();

        assert!(config.validate().is_err());

        config.adapter_id = "valid-id".to_string();
        config.layers = vec![IngestLayer::DirectEvent];
        assert!(config.validate().is_ok());
    }
}
