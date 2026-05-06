//! Anthropic provider — BYOK direct to api.anthropic.com.
//!
//! Customer supplies their own API key (stored in OS keychain). FluxForge never
//! sees the key — we just read it from the keychain at request time.
//!
//! Uses Messages API (`/v1/messages`) with `claude-sonnet-4-5` by default.

use crate::credentials::CredentialStore;
use crate::provider::{
    AiPrompt, AiProvider, AiProviderError, AiProviderId, AiResponse, AiResult,
    ProviderCapabilities,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

const DEFAULT_ENDPOINT: &str = "https://api.anthropic.com";
const DEFAULT_MODEL: &str = "claude-sonnet-4-5";
const ANTHROPIC_VERSION: &str = "2023-06-01";
const KEYCHAIN_ACCOUNT: &str = "anthropic";

/// Anthropic Claude provider (BYOK).
pub struct AnthropicProvider {
    endpoint: String,
    model: String,
    client: reqwest::Client,
    credentials: Arc<dyn CredentialStore>,
}

impl AnthropicProvider {
    /// Create with default endpoint, default model, and supplied credential store.
    pub fn new(credentials: Arc<dyn CredentialStore>) -> AiResult<Self> {
        Self::with_config(DEFAULT_ENDPOINT, DEFAULT_MODEL, credentials)
    }

    /// Create with custom endpoint, model, and credential store.
    pub fn with_config(
        endpoint: impl Into<String>,
        model: impl Into<String>,
        credentials: Arc<dyn CredentialStore>,
    ) -> AiResult<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(120))
            .connect_timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| AiProviderError::Config(format!("HTTP client: {}", e)))?;

        Ok(Self {
            endpoint: endpoint.into(),
            model: model.into(),
            client,
            credentials,
        })
    }

    /// Keychain account name where the API key is expected.
    pub fn credential_account() -> &'static str {
        KEYCHAIN_ACCOUNT
    }

    /// Pull the API key from the credential store (NotFound → Auth error).
    fn api_key(&self) -> AiResult<String> {
        self.credentials
            .get(KEYCHAIN_ACCOUNT)
            .map_err(|e| AiProviderError::Auth(format!("api key not configured: {}", e)))
    }
}

#[derive(Serialize)]
struct AnthropicRequest<'a> {
    model: &'a str,
    max_tokens: u32,
    temperature: f32,
    system: &'a str,
    messages: Vec<AnthropicMessage<'a>>,
}

#[derive(Serialize)]
struct AnthropicMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Deserialize)]
struct AnthropicResponse {
    content: Vec<AnthropicContent>,
    #[serde(default)]
    model: String,
    #[serde(default)]
    usage: Option<AnthropicUsage>,
}

#[derive(Deserialize)]
struct AnthropicContent {
    #[serde(rename = "type")]
    content_type: String,
    text: Option<String>,
}

#[derive(Deserialize)]
struct AnthropicUsage {
    #[serde(default)]
    input_tokens: u32,
    #[serde(default)]
    output_tokens: u32,
}

#[async_trait]
impl AiProvider for AnthropicProvider {
    fn id(&self) -> AiProviderId {
        AiProviderId::Anthropic
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            streaming: true,
            structured_output: true, // via prompt-driven JSON schema
            air_gapped: false,
            max_context_tokens: 200_000,
            cost_per_1m_input_usd: 3.0,
        }
    }

    fn model(&self) -> &str {
        &self.model
    }

    fn endpoint(&self) -> &str {
        &self.endpoint
    }

    async fn health_check(&self) -> AiResult<()> {
        // Use a 1-token completion as the cheapest valid round trip.
        // Even cheaper would be /v1/models, but Anthropic returns 401 without a key.
        let key = self.api_key()?;
        let url = format!("{}/v1/messages", self.endpoint);
        let body = AnthropicRequest {
            model: &self.model,
            max_tokens: 1,
            temperature: 0.0,
            system: "ping",
            messages: vec![AnthropicMessage {
                role: "user",
                content: "ping",
            }],
        };
        let resp = self
            .client
            .post(&url)
            .header("x-api-key", key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .json(&body)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("anthropic ping: {}", e)))?;

        let status = resp.status();
        if status.is_success() {
            Ok(())
        } else if status.as_u16() == 401 || status.as_u16() == 403 {
            Err(AiProviderError::Auth(format!(
                "anthropic auth rejected: {}",
                status
            )))
        } else {
            Err(AiProviderError::Network(format!(
                "anthropic ping failed: {}",
                status
            )))
        }
    }

    async fn generate(&self, prompt: &AiPrompt) -> AiResult<AiResponse> {
        let key = self.api_key()?;

        // Inject schema into the system prompt when JSON mode is requested
        // (Anthropic does not have a native `format: json` flag — schema goes inline).
        let mut system = prompt.system.clone();
        if let Some(schema) = &prompt.json_schema {
            let schema_text = serde_json::to_string(schema).unwrap_or_default();
            system.push_str("\n\nYou MUST output ONLY valid JSON matching this schema:\n");
            system.push_str(&schema_text);
            system.push_str("\nDo not wrap in markdown. Do not add commentary.");
        }

        let body = AnthropicRequest {
            model: &self.model,
            max_tokens: prompt.max_tokens,
            temperature: prompt.temperature,
            system: &system,
            messages: vec![AnthropicMessage {
                role: "user",
                content: &prompt.user,
            }],
        };

        let url = format!("{}/v1/messages", self.endpoint);
        let started = Instant::now();
        let resp = self
            .client
            .post(&url)
            .header("x-api-key", key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .json(&body)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("anthropic POST: {}", e)))?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            return Err(match status.as_u16() {
                401 | 403 => AiProviderError::Auth(text),
                429 => AiProviderError::RateLimited(text),
                400 => AiProviderError::PromptRejected(text),
                _ => AiProviderError::Network(format!("{}: {}", status, text)),
            });
        }

        let parsed: AnthropicResponse = resp
            .json()
            .await
            .map_err(|e| AiProviderError::InvalidResponse(format!("anthropic JSON: {}", e)))?;

        let text = parsed
            .content
            .into_iter()
            .filter(|c| c.content_type == "text")
            .filter_map(|c| c.text)
            .collect::<Vec<_>>()
            .join("");

        let json = if prompt.json_schema.is_some() {
            serde_json::from_str(&text).ok()
        } else {
            None
        };

        let (tin, tout) = parsed
            .usage
            .map(|u| (u.input_tokens, u.output_tokens))
            .unwrap_or((0, 0));

        Ok(AiResponse {
            text,
            json,
            tokens_input: tin,
            tokens_output: tout,
            elapsed_ms: started.elapsed().as_millis() as u32,
            model_used: if parsed.model.is_empty() {
                self.model.clone()
            } else {
                parsed.model
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::MemoryStore;

    #[test]
    fn defaults_are_byok() {
        let store = Arc::new(MemoryStore::new()) as Arc<dyn CredentialStore>;
        let p = AnthropicProvider::new(store).unwrap();
        assert_eq!(p.endpoint(), DEFAULT_ENDPOINT);
        assert_eq!(p.model(), DEFAULT_MODEL);
        assert_eq!(p.id(), AiProviderId::Anthropic);
        assert!(!p.capabilities().air_gapped);
        assert_eq!(p.capabilities().max_context_tokens, 200_000);
    }

    #[test]
    fn missing_key_produces_auth_error() {
        let store = Arc::new(MemoryStore::new()) as Arc<dyn CredentialStore>;
        let p = AnthropicProvider::new(store).unwrap();
        match p.api_key() {
            Err(AiProviderError::Auth(_)) => {}
            other => panic!("expected Auth, got {:?}", other),
        }
    }

    #[test]
    fn key_stored_then_retrieved() {
        let store = Arc::new(MemoryStore::new());
        store.put("anthropic", "sk-ant-test").unwrap();
        let p = AnthropicProvider::new(store as Arc<dyn CredentialStore>).unwrap();
        assert_eq!(p.api_key().unwrap(), "sk-ant-test");
    }

    #[tokio::test]
    async fn health_check_without_key_is_auth_error() {
        let store = Arc::new(MemoryStore::new()) as Arc<dyn CredentialStore>;
        let p = AnthropicProvider::with_config("http://127.0.0.1:1", "claude-test", store).unwrap();
        match p.health_check().await {
            Err(AiProviderError::Auth(_)) => {}
            other => panic!("expected Auth, got {:?}", other),
        }
    }
}
