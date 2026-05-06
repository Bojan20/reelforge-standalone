//! Provider registry — runtime selection of which `AiProvider` is active.
//!
//! The registry is a single Arc-shared object that:
//! - Holds the current provider selection (which backend, which model, which endpoint)
//! - Builds a fresh provider instance on demand from the selection
//! - Lets the UI swap providers without restarting the engine
//!
//! Thread safety: selection is in `RwLock` — readers are cheap, writers (Settings UI)
//! are rare. Provider construction is on-demand (cheap clone of HTTP client).

use crate::credentials::CredentialStore;
use crate::provider::{AiProvider, AiProviderError, AiProviderId, AiProviderInfo, AiResult};
use crate::providers::{AnthropicProvider, AzureOpenAIProvider, OllamaProvider};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// User-facing settings for which provider is active and how it's configured.
///
/// This struct is the JSON shape stored on disk (e.g.
/// `~/Library/Application Support/FluxForge/composer.json`) and exchanged with
/// the Flutter Settings UI.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderSelection {
    /// Active backend.
    pub provider: AiProviderId,

    /// Ollama config (used when `provider == Ollama`).
    pub ollama: OllamaConfig,

    /// Anthropic config (used when `provider == Anthropic`).
    pub anthropic: AnthropicConfig,

    /// Azure OpenAI config (used when `provider == AzureOpenAI`).
    pub azure: AzureConfig,
}

impl Default for ProviderSelection {
    fn default() -> Self {
        Self {
            // Default to Ollama because it requires no credentials and respects
            // air-gapped deployments out of the box.
            provider: AiProviderId::Ollama,
            ollama: OllamaConfig::default(),
            anthropic: AnthropicConfig::default(),
            azure: AzureConfig::default(),
        }
    }
}

/// Per-backend configuration: Ollama.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OllamaConfig {
    /// HTTP endpoint (default `http://127.0.0.1:11434`).
    pub endpoint: String,
    /// Model name (default `llama3.1:70b`).
    pub model: String,
}

impl Default for OllamaConfig {
    fn default() -> Self {
        Self {
            endpoint: "http://127.0.0.1:11434".to_string(),
            model: "llama3.1:70b".to_string(),
        }
    }
}

/// Per-backend configuration: Anthropic.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AnthropicConfig {
    /// API endpoint (default `https://api.anthropic.com`).
    pub endpoint: String,
    /// Model name (default `claude-sonnet-4-5`).
    pub model: String,
}

impl Default for AnthropicConfig {
    fn default() -> Self {
        Self {
            endpoint: "https://api.anthropic.com".to_string(),
            model: "claude-sonnet-4-5".to_string(),
        }
    }
}

/// Per-backend configuration: Azure OpenAI.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureConfig {
    /// Resource endpoint (e.g. `https://my-tenant.openai.azure.com`).
    pub endpoint: String,
    /// Deployment name (Azure-side deployment ID).
    pub deployment: String,
    /// API version.
    pub api_version: String,
}

impl Default for AzureConfig {
    fn default() -> Self {
        Self {
            endpoint: String::new(),
            deployment: String::new(),
            api_version: "2024-08-01-preview".to_string(),
        }
    }
}

/// The runtime registry — one per app instance, shared as `Arc<ProviderRegistry>`.
pub struct ProviderRegistry {
    selection: RwLock<ProviderSelection>,
    credentials: Arc<dyn CredentialStore>,
}

impl ProviderRegistry {
    /// Create a new registry with the given selection and credential store.
    pub fn new(selection: ProviderSelection, credentials: Arc<dyn CredentialStore>) -> Self {
        Self {
            selection: RwLock::new(selection),
            credentials,
        }
    }

    /// Read the current selection (cheap clone).
    pub fn selection(&self) -> ProviderSelection {
        self.selection.read().clone()
    }

    /// Replace the selection (UI calls this when the user clicks Save in Settings).
    pub fn set_selection(&self, new: ProviderSelection) {
        *self.selection.write() = new;
    }

    /// Build a fresh provider instance from the current selection.
    ///
    /// Returns a `Box<dyn AiProvider>` because the trait object must outlive
    /// the registry borrow.
    pub fn build(&self) -> AiResult<Box<dyn AiProvider>> {
        let sel = self.selection.read().clone();
        match sel.provider {
            AiProviderId::Ollama => {
                let p = OllamaProvider::with_config(sel.ollama.endpoint, sel.ollama.model)?;
                Ok(Box::new(p))
            }
            AiProviderId::Anthropic => {
                let p = AnthropicProvider::with_config(
                    sel.anthropic.endpoint,
                    sel.anthropic.model,
                    Arc::clone(&self.credentials),
                )?;
                Ok(Box::new(p))
            }
            AiProviderId::AzureOpenAI => {
                if sel.azure.endpoint.is_empty() || sel.azure.deployment.is_empty() {
                    return Err(AiProviderError::Config(
                        "azure endpoint / deployment not configured".to_string(),
                    ));
                }
                let p = AzureOpenAIProvider::with_api_version(
                    sel.azure.endpoint,
                    sel.azure.deployment,
                    sel.azure.api_version,
                    Arc::clone(&self.credentials),
                )?;
                Ok(Box::new(p))
            }
        }
    }

    /// Run a health check against the currently-selected provider and return
    /// a structured info object suitable for the Settings UI status panel.
    pub async fn describe_active(&self) -> AiProviderInfo {
        match self.build() {
            Ok(provider) => {
                let id = provider.id();
                let model = provider.model().to_string();
                let endpoint = provider.endpoint().to_string();
                let capabilities = provider.capabilities();
                let healthy = provider.health_check().await.is_ok();
                AiProviderInfo {
                    id,
                    model,
                    endpoint,
                    capabilities,
                    healthy,
                }
            }
            Err(_) => AiProviderInfo {
                id: self.selection().provider,
                model: String::new(),
                endpoint: String::new(),
                capabilities: Default::default(),
                healthy: false,
            },
        }
    }

    /// Access the credential store (used by Settings UI to put / delete keys).
    pub fn credentials(&self) -> &Arc<dyn CredentialStore> {
        &self.credentials
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::MemoryStore;

    fn make_registry() -> Arc<ProviderRegistry> {
        Arc::new(ProviderRegistry::new(
            ProviderSelection::default(),
            Arc::new(MemoryStore::new()),
        ))
    }

    #[test]
    fn default_selection_is_ollama() {
        let r = make_registry();
        assert_eq!(r.selection().provider, AiProviderId::Ollama);
    }

    #[test]
    fn set_selection_persists() {
        let r = make_registry();
        let mut s = r.selection();
        s.provider = AiProviderId::Anthropic;
        r.set_selection(s);
        assert_eq!(r.selection().provider, AiProviderId::Anthropic);
    }

    #[test]
    fn build_ollama_succeeds_without_credentials() {
        let r = make_registry();
        let p = r.build().unwrap();
        assert_eq!(p.id(), AiProviderId::Ollama);
    }

    #[test]
    fn build_azure_fails_without_endpoint() {
        let r = make_registry();
        let mut s = r.selection();
        s.provider = AiProviderId::AzureOpenAI;
        // Default azure config has empty endpoint / deployment.
        r.set_selection(s);
        match r.build() {
            Err(AiProviderError::Config(_)) => {}
            other => panic!("expected Config error, got {:?}", other.is_ok()),
        }
    }

    #[test]
    fn build_azure_succeeds_with_full_config() {
        let r = make_registry();
        let mut s = r.selection();
        s.provider = AiProviderId::AzureOpenAI;
        s.azure.endpoint = "https://my-tenant.openai.azure.com".to_string();
        s.azure.deployment = "gpt-4o".to_string();
        r.set_selection(s);
        let p = r.build().unwrap();
        assert_eq!(p.id(), AiProviderId::AzureOpenAI);
    }

    #[test]
    fn selection_round_trip_serde() {
        let s = ProviderSelection::default();
        let j = serde_json::to_string(&s).unwrap();
        let back: ProviderSelection = serde_json::from_str(&j).unwrap();
        assert_eq!(s, back);
    }
}
