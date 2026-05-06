//! Azure OpenAI provider — enterprise tenant deployment.
//!
//! Customer configures:
//! - Resource endpoint (e.g. `https://my-tenant.openai.azure.com`)
//! - Deployment name (their Azure-side model deployment ID)
//! - API version (e.g. `2024-08-01-preview`)
//! - API key (stored in OS keychain under account `azure_openai`)
//!
//! Differences from public OpenAI:
//! - Endpoint includes `/openai/deployments/{deployment}/chat/completions`
//! - API key sent via `api-key` header (NOT `Authorization: Bearer`)
//! - Region/tenant lockdown — data stays in customer's Azure region
//!
//! Native JSON mode supported via `response_format: { type: "json_object" }`.

use crate::credentials::CredentialStore;
use crate::provider::{
    AiPrompt, AiProvider, AiProviderError, AiProviderId, AiResponse, AiResult,
    ProviderCapabilities,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

const DEFAULT_API_VERSION: &str = "2024-08-01-preview";
const KEYCHAIN_ACCOUNT: &str = "azure_openai";

/// Azure OpenAI provider (customer's tenant).
pub struct AzureOpenAIProvider {
    endpoint: String,
    deployment: String,
    api_version: String,
    client: reqwest::Client,
    credentials: Arc<dyn CredentialStore>,
}

impl AzureOpenAIProvider {
    /// Create with required endpoint + deployment, default API version.
    pub fn new(
        endpoint: impl Into<String>,
        deployment: impl Into<String>,
        credentials: Arc<dyn CredentialStore>,
    ) -> AiResult<Self> {
        Self::with_api_version(endpoint, deployment, DEFAULT_API_VERSION, credentials)
    }

    /// Create with all parameters explicit.
    pub fn with_api_version(
        endpoint: impl Into<String>,
        deployment: impl Into<String>,
        api_version: impl Into<String>,
        credentials: Arc<dyn CredentialStore>,
    ) -> AiResult<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(120))
            .connect_timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| AiProviderError::Config(format!("HTTP client: {}", e)))?;

        let endpoint: String = endpoint.into();
        let endpoint = endpoint.trim_end_matches('/').to_string();

        Ok(Self {
            endpoint,
            deployment: deployment.into(),
            api_version: api_version.into(),
            client,
            credentials,
        })
    }

    /// Keychain account name where the Azure API key is expected.
    pub fn credential_account() -> &'static str {
        KEYCHAIN_ACCOUNT
    }

    fn api_key(&self) -> AiResult<String> {
        self.credentials
            .get(KEYCHAIN_ACCOUNT)
            .map_err(|e| AiProviderError::Auth(format!("api key not configured: {}", e)))
    }

    fn chat_url(&self) -> String {
        format!(
            "{}/openai/deployments/{}/chat/completions?api-version={}",
            self.endpoint, self.deployment, self.api_version
        )
    }
}

#[derive(Serialize)]
struct AzureRequest<'a> {
    messages: Vec<AzureMessage<'a>>,
    temperature: f32,
    max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<AzureResponseFormat>,
}

#[derive(Serialize)]
struct AzureMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Serialize)]
struct AzureResponseFormat {
    #[serde(rename = "type")]
    fmt: &'static str,
}

#[derive(Deserialize)]
struct AzureResponse {
    choices: Vec<AzureChoice>,
    #[serde(default)]
    model: String,
    #[serde(default)]
    usage: Option<AzureUsage>,
}

#[derive(Deserialize)]
struct AzureChoice {
    message: AzureChoiceMessage,
}

#[derive(Deserialize)]
struct AzureChoiceMessage {
    content: String,
}

#[derive(Deserialize)]
struct AzureUsage {
    #[serde(default)]
    prompt_tokens: u32,
    #[serde(default)]
    completion_tokens: u32,
}

#[async_trait]
impl AiProvider for AzureOpenAIProvider {
    fn id(&self) -> AiProviderId {
        AiProviderId::AzureOpenAI
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            streaming: true,
            structured_output: true, // native response_format
            air_gapped: false,
            max_context_tokens: 128_000,
            cost_per_1m_input_usd: 2.5, // approximate; varies per deployment
        }
    }

    fn model(&self) -> &str {
        &self.deployment
    }

    fn endpoint(&self) -> &str {
        &self.endpoint
    }

    async fn health_check(&self) -> AiResult<()> {
        let key = self.api_key()?;
        let body = AzureRequest {
            messages: vec![AzureMessage {
                role: "user",
                content: "ping",
            }],
            temperature: 0.0,
            max_tokens: 1,
            response_format: None,
        };
        let resp = self
            .client
            .post(self.chat_url())
            .header("api-key", key)
            .json(&body)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("azure ping: {}", e)))?;

        let status = resp.status();
        if status.is_success() {
            Ok(())
        } else if matches!(status.as_u16(), 401 | 403) {
            Err(AiProviderError::Auth(format!(
                "azure auth rejected: {}",
                status
            )))
        } else {
            Err(AiProviderError::Network(format!(
                "azure ping failed: {}",
                status
            )))
        }
    }

    async fn generate(&self, prompt: &AiPrompt) -> AiResult<AiResponse> {
        let key = self.api_key()?;

        let response_format = if prompt.json_schema.is_some() {
            Some(AzureResponseFormat { fmt: "json_object" })
        } else {
            None
        };

        // For json_object mode the schema must be conveyed in the system prompt
        // (Azure's `json_object` only enforces validity, not schema conformance).
        let mut system = prompt.system.clone();
        if let Some(schema) = &prompt.json_schema {
            let schema_text = serde_json::to_string(schema).unwrap_or_default();
            system.push_str("\n\nReturn ONLY a JSON object matching this schema:\n");
            system.push_str(&schema_text);
        }

        let body = AzureRequest {
            messages: vec![
                AzureMessage {
                    role: "system",
                    content: &system,
                },
                AzureMessage {
                    role: "user",
                    content: &prompt.user,
                },
            ],
            temperature: prompt.temperature,
            max_tokens: prompt.max_tokens,
            response_format,
        };

        let started = Instant::now();
        let resp = self
            .client
            .post(self.chat_url())
            .header("api-key", key)
            .json(&body)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("azure POST: {}", e)))?;

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

        let parsed: AzureResponse = resp
            .json()
            .await
            .map_err(|e| AiProviderError::InvalidResponse(format!("azure JSON: {}", e)))?;

        let text = parsed
            .choices
            .into_iter()
            .next()
            .map(|c| c.message.content)
            .unwrap_or_default();

        let json = if prompt.json_schema.is_some() {
            serde_json::from_str(&text).ok()
        } else {
            None
        };

        let (tin, tout) = parsed
            .usage
            .map(|u| (u.prompt_tokens, u.completion_tokens))
            .unwrap_or((0, 0));

        Ok(AiResponse {
            text,
            json,
            tokens_input: tin,
            tokens_output: tout,
            elapsed_ms: started.elapsed().as_millis() as u32,
            model_used: if parsed.model.is_empty() {
                self.deployment.clone()
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

    fn store() -> Arc<dyn CredentialStore> {
        Arc::new(MemoryStore::new())
    }

    #[test]
    fn url_assembled_correctly() {
        let p = AzureOpenAIProvider::new(
            "https://my-tenant.openai.azure.com",
            "gpt-4o-deploy",
            store(),
        )
        .unwrap();
        assert_eq!(
            p.chat_url(),
            "https://my-tenant.openai.azure.com/openai/deployments/gpt-4o-deploy/chat/completions?api-version=2024-08-01-preview"
        );
    }

    #[test]
    fn trailing_slash_in_endpoint_stripped() {
        let p =
            AzureOpenAIProvider::new("https://my-tenant.openai.azure.com/", "deploy", store())
                .unwrap();
        assert!(!p.endpoint().ends_with('/'));
    }

    #[test]
    fn capabilities_marks_non_air_gapped() {
        let p = AzureOpenAIProvider::new("https://x.openai.azure.com", "deploy", store()).unwrap();
        assert!(!p.capabilities().air_gapped);
        assert!(p.capabilities().structured_output);
    }

    #[test]
    fn id_and_model_correct() {
        let p = AzureOpenAIProvider::new("https://x.openai.azure.com", "gpt-4o-eu", store()).unwrap();
        assert_eq!(p.id(), AiProviderId::AzureOpenAI);
        assert_eq!(p.model(), "gpt-4o-eu");
    }

    #[tokio::test]
    async fn health_check_without_key_is_auth_error() {
        let p = AzureOpenAIProvider::new("https://x.openai.azure.com", "deploy", store()).unwrap();
        match p.health_check().await {
            Err(AiProviderError::Auth(_)) => {}
            other => panic!("expected Auth, got {:?}", other),
        }
    }
}
