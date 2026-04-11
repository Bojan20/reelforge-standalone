// file: crates/rf-brain-router/src/providers/claude.rs
//! Claude API Provider — Anthropic's Claude Opus and Sonnet.
//!
//! Uses the Messages API (https://api.anthropic.com/v1/messages).
//! Claude Opus: architecture, deep reasoning, 1M context window.
//! Claude Sonnet: fast daily driver for code and tests.

use crate::config::AnthropicConfig;
use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use chrono::Utc;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};

/// Anthropic Claude provider (Opus + Sonnet).
pub struct ClaudeProvider {
    config: AnthropicConfig,
    client: reqwest::Client,
    available: AtomicBool,
}

impl ClaudeProvider {
    pub fn new(config: AnthropicConfig) -> Self {
        let available = config.api_key.is_some();
        let timeout = std::time::Duration::from_secs(if config.timeout_secs > 0 {
            config.timeout_secs
        } else {
            120
        });

        let client = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .unwrap_or_default();

        Self {
            config,
            client,
            available: AtomicBool::new(available),
        }
    }

    async fn do_query(&self, request: &BrainRequest) -> Result<BrainResponse, BrainError> {
        let api_key = self.config.api_key.as_deref().ok_or(BrainError::NotConfigured {
            provider: "anthropic".into(),
        })?;

        let url = format!("{}/v1/messages", self.config.base_url);

        // Build messages array
        let mut messages = Vec::new();
        if !request.context.is_empty() {
            messages.push(serde_json::json!({
                "role": "user",
                "content": format!("[Kontekst]: {}", request.context)
            }));
            messages.push(serde_json::json!({
                "role": "assistant",
                "content": "Razumem kontekst. Nastavljam."
            }));
        }
        messages.push(serde_json::json!({
            "role": "user",
            "content": request.query
        }));

        let mut body = serde_json::json!({
            "model": request.model.api_model_id(),
            "max_tokens": request.max_tokens,
            "messages": messages,
        });

        // Add system prompt if present
        if let Some(ref system) = request.system_prompt {
            body["system"] = serde_json::json!(system);
        }

        // Add temperature (Claude API accepts 0.0-1.0)
        if request.temperature > 0.0 {
            body["temperature"] = serde_json::json!(request.temperature.min(1.0));
        }

        let start = std::time::Instant::now();

        let response = self
            .client
            .post(&url)
            .header("x-api-key", api_key)
            .header("anthropic-version", &self.config.api_version)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    BrainError::Timeout {
                        provider: "anthropic".into(),
                        timeout_ms: self.config.timeout_secs * 1000,
                    }
                } else {
                    BrainError::Network {
                        message: e.to_string(),
                    }
                }
            })?;

        let latency_ms = start.elapsed().as_millis() as u64;
        let status = response.status().as_u16();

        if status == 429 {
            // Extract retry-after if available
            let retry_after = response
                .headers()
                .get("retry-after")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(30);

            return Err(BrainError::RateLimited {
                provider: "anthropic".into(),
                retry_after_secs: retry_after,
            });
        }

        let response_body: serde_json::Value = response.json().await.map_err(|e| {
            BrainError::ApiError {
                provider: "anthropic".into(),
                status,
                message: e.to_string(),
            }
        })?;

        if status != 200 {
            let error_msg = response_body["error"]["message"]
                .as_str()
                .unwrap_or("Unknown error")
                .to_string();
            return Err(BrainError::ApiError {
                provider: "anthropic".into(),
                status,
                message: error_msg,
            });
        }

        // Extract content from response
        let content = response_body["content"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|block| block["text"].as_str())
            .unwrap_or("")
            .to_string();

        let input_tokens = response_body["usage"]["input_tokens"]
            .as_u64()
            .unwrap_or(0);
        let output_tokens = response_body["usage"]["output_tokens"]
            .as_u64()
            .unwrap_or(0);

        let estimated_cost =
            BrainResponse::calculate_cost(&request.model, input_tokens, output_tokens);

        Ok(BrainResponse {
            request_id: request.id.clone(),
            model: request.model.clone(),
            content,
            input_tokens,
            output_tokens,
            latency_ms,
            received_at: Utc::now(),
            is_fallback: false,
            estimated_cost_usd: estimated_cost,
        })
    }
}

impl BrainProviderAsync for ClaudeProvider {
    fn name(&self) -> &str {
        "anthropic"
    }

    fn supported_models(&self) -> &[ModelId] {
        &[ModelId::ClaudeOpus, ModelId::ClaudeSonnet]
    }

    fn is_available(&self) -> bool {
        self.available.load(Ordering::Relaxed)
    }

    fn query<'a>(
        &'a self,
        request: &'a BrainRequest,
    ) -> Pin<Box<dyn Future<Output = Result<BrainResponse, BrainError>> + Send + 'a>> {
        Box::pin(self.do_query(request))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_available_without_key() {
        let config = AnthropicConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = ClaudeProvider::new(config);
        assert!(!provider.is_available());
    }

    #[test]
    fn available_with_key() {
        let config = AnthropicConfig {
            api_key: Some("test-key".into()),
            ..Default::default()
        };
        let provider = ClaudeProvider::new(config);
        assert!(provider.is_available());
    }

    #[test]
    fn supported_models() {
        let provider = ClaudeProvider::new(AnthropicConfig::default());
        let models = provider.supported_models();
        assert!(models.contains(&ModelId::ClaudeOpus));
        assert!(models.contains(&ModelId::ClaudeSonnet));
        assert!(!models.contains(&ModelId::Gpt4o));
    }

    #[test]
    fn provider_name() {
        let provider = ClaudeProvider::new(AnthropicConfig::default());
        assert_eq!(provider.name(), "anthropic");
    }

    #[tokio::test]
    async fn query_fails_without_key() {
        let config = AnthropicConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = ClaudeProvider::new(config);
        let request = BrainRequest::new("test", ModelId::ClaudeOpus);

        let result = provider.do_query(&request).await;
        assert!(matches!(result, Err(BrainError::NotConfigured { .. })));
    }
}
