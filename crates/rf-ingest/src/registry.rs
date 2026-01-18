//! Adapter Registry — Central registry for all adapters

use std::collections::HashMap;
use std::sync::Arc;

use crate::adapter::EngineAdapter;

/// Central registry for engine adapters
#[derive(Default)]
pub struct AdapterRegistry {
    adapters: HashMap<String, Arc<dyn EngineAdapter>>,
}

impl AdapterRegistry {
    /// Create empty registry
    pub fn new() -> Self {
        Self::default()
    }

    /// Register an adapter
    pub fn register(&mut self, adapter: Arc<dyn EngineAdapter>) {
        self.adapters
            .insert(adapter.adapter_id().to_string(), adapter);
    }

    /// Get adapter by ID
    pub fn get(&self, adapter_id: &str) -> Option<Arc<dyn EngineAdapter>> {
        self.adapters.get(adapter_id).cloned()
    }

    /// List all adapter IDs
    pub fn list_ids(&self) -> Vec<&str> {
        self.adapters.keys().map(|s| s.as_str()).collect()
    }

    /// List all adapters
    pub fn list_adapters(&self) -> Vec<Arc<dyn EngineAdapter>> {
        self.adapters.values().cloned().collect()
    }

    /// Get adapter count
    pub fn len(&self) -> usize {
        self.adapters.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.adapters.is_empty()
    }

    /// Remove adapter by ID
    pub fn remove(&mut self, adapter_id: &str) -> Option<Arc<dyn EngineAdapter>> {
        self.adapters.remove(adapter_id)
    }

    /// Check if adapter exists
    pub fn contains(&self, adapter_id: &str) -> bool {
        self.adapters.contains_key(adapter_id)
    }

    /// Try to auto-detect adapter from JSON
    pub fn detect_adapter(&self, json: &serde_json::Value) -> Option<Arc<dyn EngineAdapter>> {
        for adapter in self.adapters.values() {
            if adapter.parse_json(json).is_ok() {
                return Some(adapter.clone());
            }
        }
        None
    }
}

/// Registry info for UI display
#[derive(Debug, Clone)]
pub struct AdapterInfo {
    pub adapter_id: String,
    pub company_name: String,
    pub engine_name: String,
}

impl AdapterRegistry {
    /// Get info for all adapters (for UI)
    pub fn get_adapter_infos(&self) -> Vec<AdapterInfo> {
        self.adapters
            .values()
            .map(|a| AdapterInfo {
                adapter_id: a.adapter_id().to_string(),
                company_name: a.company_name().to_string(),
                engine_name: a.engine_name().to_string(),
            })
            .collect()
    }

    /// Get adapter count
    pub fn count(&self) -> usize {
        self.adapters.len()
    }

    /// Get all adapter IDs
    pub fn adapter_ids(&self) -> Vec<String> {
        self.adapters.keys().cloned().collect()
    }

    /// Register a config-based adapter
    pub fn register_config(&mut self, config: crate::config::AdapterConfig) {
        let adapter = Arc::new(crate::adapter::ConfigBasedAdapter::new(config));
        self.register(adapter);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::adapter::{AdapterError, IngestLayer};
    use crate::config::AdapterConfig;
    use rf_stage::{StageEvent, StageTrace};

    // Mock adapter for testing
    struct MockAdapter {
        id: String,
    }

    impl EngineAdapter for MockAdapter {
        fn adapter_id(&self) -> &str {
            &self.id
        }
        fn company_name(&self) -> &str {
            "Mock"
        }
        fn engine_name(&self) -> &str {
            "MockEngine"
        }
        fn supported_layers(&self) -> Vec<IngestLayer> {
            vec![IngestLayer::DirectEvent]
        }
        fn parse_json(&self, _json: &serde_json::Value) -> Result<StageTrace, AdapterError> {
            Ok(StageTrace::new("test", "mock"))
        }
        fn parse_event(
            &self,
            _event: &serde_json::Value,
        ) -> Result<Option<StageEvent>, AdapterError> {
            Ok(None)
        }
        fn validate_config(&self, _config: &AdapterConfig) -> Result<(), AdapterError> {
            Ok(())
        }
        fn default_config(&self) -> AdapterConfig {
            AdapterConfig::new(&self.id, "Mock", "MockEngine")
        }
    }

    #[test]
    fn test_registry_operations() {
        let mut registry = AdapterRegistry::new();

        let adapter = Arc::new(MockAdapter {
            id: "mock-1".to_string(),
        });
        registry.register(adapter);

        assert!(registry.contains("mock-1"));
        assert!(!registry.contains("mock-2"));
        assert_eq!(registry.len(), 1);

        let retrieved = registry.get("mock-1");
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().adapter_id(), "mock-1");
    }
}
