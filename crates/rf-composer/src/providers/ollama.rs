//! Ollama provider — local, air-gapped LLM inference.
//!
//! Talks to `http://127.0.0.1:11434/api/chat` by default. No credentials needed
//! (Ollama is local). Customer must have pulled the model (e.g. `ollama pull llama3.1:70b`).
//!
//! Supports JSON mode via Ollama's `format: "json"` parameter.

use crate::provider::{
    AiPrompt, AiProvider, AiProviderError, AiProviderId, AiResponse, AiResult,
    ProviderCapabilities,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use std::time::Instant;

const DEFAULT_ENDPOINT: &str = "http://127.0.0.1:11434";
const DEFAULT_MODEL: &str = "llama3.1:70b";

/// Local Ollama LLM provider.
pub struct OllamaProvider {
    endpoint: String,
    model: String,
    client: reqwest::Client,
}

impl OllamaProvider {
    /// Create with default `127.0.0.1:11434` and `llama3.1:70b`.
    pub fn new() -> AiResult<Self> {
        Self::with_config(DEFAULT_ENDPOINT, DEFAULT_MODEL)
    }

    /// Create with custom endpoint and model.
    pub fn with_config(endpoint: impl Into<String>, model: impl Into<String>) -> AiResult<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(120)) // local but slow on big models
            .connect_timeout(Duration::from_secs(5))
            .build()
            .map_err(|e| AiProviderError::Config(format!("HTTP client: {}", e)))?;

        Ok(Self {
            endpoint: endpoint.into(),
            model: model.into(),
            client,
        })
    }
}

#[derive(Serialize)]
struct OllamaChatRequest<'a> {
    model: &'a str,
    messages: Vec<OllamaMessage<'a>>,
    stream: bool,
    options: OllamaOptions,
    #[serde(skip_serializing_if = "Option::is_none")]
    format: Option<&'a str>,
}

#[derive(Serialize)]
struct OllamaMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Serialize)]
struct OllamaOptions {
    temperature: f32,
    num_predict: i32,
}

#[derive(Deserialize)]
struct OllamaChatResponse {
    message: OllamaResponseMessage,
    #[serde(default)]
    prompt_eval_count: u32,
    #[serde(default)]
    eval_count: u32,
    #[serde(default)]
    model: String,
}

#[derive(Deserialize)]
struct OllamaResponseMessage {
    content: String,
}

#[async_trait]
impl AiProvider for OllamaProvider {
    fn id(&self) -> AiProviderId {
        AiProviderId::Ollama
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            streaming: true,        // Ollama supports stream:true; we don't use it for now
            structured_output: true, // format:"json" mode
            air_gapped: true,
            max_context_tokens: 8192,
            cost_per_1m_input_usd: 0.0,
        }
    }

    fn model(&self) -> &str {
        &self.model
    }

    fn endpoint(&self) -> &str {
        &self.endpoint
    }

    async fn health_check(&self) -> AiResult<()> {
        let url = format!("{}/api/tags", self.endpoint);
        let resp = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("ollama unreachable: {}", e)))?;

        if !resp.status().is_success() {
            return Err(AiProviderError::Network(format!(
                "ollama /api/tags returned {}",
                resp.status()
            )));
        }
        Ok(())
    }

    async fn generate(&self, prompt: &AiPrompt) -> AiResult<AiResponse> {
        let url = format!("{}/api/chat", self.endpoint);
        let format = if prompt.json_schema.is_some() {
            Some("json")
        } else {
            None
        };

        let body = OllamaChatRequest {
            model: &self.model,
            messages: vec![
                OllamaMessage {
                    role: "system",
                    content: &prompt.system,
                },
                OllamaMessage {
                    role: "user",
                    content: &prompt.user,
                },
            ],
            stream: false,
            options: OllamaOptions {
                temperature: prompt.temperature,
                num_predict: prompt.max_tokens as i32,
            },
            format,
        };

        let started = Instant::now();
        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| AiProviderError::Network(format!("POST /api/chat: {}", e)))?;

        let status = resp.status();
        if !status.is_success() {
            let body_text = resp.text().await.unwrap_or_default();
            return Err(if status.as_u16() == 429 {
                AiProviderError::RateLimited(body_text)
            } else if status.is_client_error() {
                AiProviderError::PromptRejected(format!("{}: {}", status, body_text))
            } else {
                AiProviderError::Network(format!("{}: {}", status, body_text))
            });
        }

        let parsed: OllamaChatResponse = resp
            .json()
            .await
            .map_err(|e| AiProviderError::InvalidResponse(format!("ollama JSON: {}", e)))?;

        let text = parsed.message.content;
        let json = if format == Some("json") {
            serde_json::from_str(&text).ok()
        } else {
            None
        };

        Ok(AiResponse {
            text,
            json,
            tokens_input: parsed.prompt_eval_count,
            tokens_output: parsed.eval_count,
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

    #[test]
    fn defaults_are_local() {
        let p = OllamaProvider::new().unwrap();
        assert_eq!(p.endpoint(), DEFAULT_ENDPOINT);
        assert_eq!(p.model(), DEFAULT_MODEL);
        assert_eq!(p.id(), AiProviderId::Ollama);
        assert!(p.capabilities().air_gapped);
        assert_eq!(p.capabilities().cost_per_1m_input_usd, 0.0);
    }

    #[test]
    fn custom_config_applied() {
        let p = OllamaProvider::with_config("http://10.0.0.5:11434", "qwen2.5:32b").unwrap();
        assert_eq!(p.endpoint(), "http://10.0.0.5:11434");
        assert_eq!(p.model(), "qwen2.5:32b");
    }

    #[tokio::test]
    async fn health_check_unreachable_returns_network_error() {
        let p = OllamaProvider::with_config("http://127.0.0.1:1", "x").unwrap();
        match p.health_check().await {
            Err(AiProviderError::Network(_)) => {}
            other => panic!("expected Network error, got {:?}", other),
        }
    }
}
