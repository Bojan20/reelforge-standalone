//! Engine Adapter trait and base implementations

use rf_stage::{StageEvent, StageTrace};
use serde_json::Value;
use thiserror::Error;

use crate::config::AdapterConfig;

/// Errors that can occur during adaptation
#[derive(Debug, Error)]
pub enum AdapterError {
    #[error("Failed to parse JSON: {0}")]
    JsonParse(#[from] serde_json::Error),

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("Invalid event format: {0}")]
    InvalidFormat(String),

    #[error("Unknown event: {0}")]
    UnknownEvent(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Validation failed: {0}")]
    ValidationFailed(String),
}

/// Ingest layer capability
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IngestLayer {
    /// Layer 1: Direct event name mapping
    DirectEvent,
    /// Layer 2: State snapshot diff derivation
    SnapshotDiff,
    /// Layer 3: Rule-based heuristic reconstruction
    RuleBased,
}

/// Engine adapter trait — converts engine-specific data to canonical STAGES
pub trait EngineAdapter: Send + Sync {
    /// Unique adapter identifier (e.g., "igt-avp", "aristocrat-helix")
    fn adapter_id(&self) -> &str;

    /// Company/engine name for display
    fn company_name(&self) -> &str;

    /// Engine/platform name
    fn engine_name(&self) -> &str;

    /// Supported ingest layers
    fn supported_layers(&self) -> Vec<IngestLayer>;

    /// Parse a complete JSON document into a StageTrace
    fn parse_json(&self, json: &Value) -> Result<StageTrace, AdapterError>;

    /// Parse a single event from a stream (for live mode)
    fn parse_event(&self, event: &Value) -> Result<Option<StageEvent>, AdapterError>;

    /// Validate adapter configuration
    fn validate_config(&self, config: &AdapterConfig) -> Result<(), AdapterError>;

    /// Get default configuration for this adapter
    fn default_config(&self) -> AdapterConfig;
}

/// Base adapter implementation using configuration
pub struct ConfigBasedAdapter {
    config: AdapterConfig,
}

impl ConfigBasedAdapter {
    pub fn new(config: AdapterConfig) -> Self {
        Self { config }
    }

    pub fn config(&self) -> &AdapterConfig {
        &self.config
    }
}

impl EngineAdapter for ConfigBasedAdapter {
    fn adapter_id(&self) -> &str {
        &self.config.adapter_id
    }

    fn company_name(&self) -> &str {
        &self.config.company_name
    }

    fn engine_name(&self) -> &str {
        &self.config.engine_name
    }

    fn supported_layers(&self) -> Vec<IngestLayer> {
        self.config.layers.clone()
    }

    fn parse_json(&self, json: &Value) -> Result<StageTrace, AdapterError> {
        crate::layer_event::parse_with_config(json, &self.config)
    }

    fn parse_event(&self, event: &Value) -> Result<Option<StageEvent>, AdapterError> {
        crate::layer_event::parse_single_event(event, &self.config)
    }

    fn validate_config(&self, config: &AdapterConfig) -> Result<(), AdapterError> {
        config.validate()
    }

    fn default_config(&self) -> AdapterConfig {
        self.config.clone()
    }
}
