// file: crates/rf-brain-router/src/providers/openai.rs
//! OpenAI API Provider — GPT-4o and GPT-4o-mini.
//!
//! Uses the Chat Completions API (https://api.openai.com/v1/chat/completions).
//! GPT-4o: creative tasks, UI/UX, marketing, broad knowledge.
//! GPT-4o-mini: cheap fallback for simple tasks.

use crate::config::OpenAiConfig;
use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use chrono::Utc;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};

/// OpenAI provider (GPT-4o + GPT-4o-mini).
pub struct OpenAiProvider {
    config: OpenAiConfig,
    client: reqwest::Client,
    available: AtomicBool,
}

impl OpenAiProvider {
    pub fn new(config: OpenAiConfig) -> Self {
        let available = config.api_key.is_some();
        let timeout = std::time::Duration::from_secs(if config.timeout_secs > 0 {
            config.timeout_secs
        } else {
            60
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
            provider: "openai".into(),
        })?;

        let url = format!("{}/v1/chat/completions", self.config.base_url);

        let mut messages = Vec::new();

        if let Some(ref system) = request.system_prompt {
            messages.push(serde_json::json!({
                "role": "system",
                "content": system
            }));
        }

        if !request.context.is_empty() {
            messages.push(serde_json::json!({
                "role": "user",
                "content": format!("[Kontekst]: {}", request.context)
            }));
            messages.push(serde_json::json!({
                "role": "assistant",
                "content": "Razumem kontekst."
            }));
        }

        messages.push(serde_json::json!({
            "role": "user",
            "content": request.query
        }));

        let body = serde_json::json!({
            "model": request.model.api_model_id(),
            "messages": messages,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "stream": false,
        });

        let start = std::time::Instant::now();

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    BrainError::Timeout {
                        provider: "openai".into(),
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
            let retry_after = response
                .headers()
                .get("retry-after")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(30);

            return Err(BrainError::RateLimited {
                provider: "openai".into(),
                retry_after_secs: retry_after,
            });
        }

        let response_body: serde_json::Value = response.json().await.map_err(|e| {
            BrainError::ApiError {
                provider: "openai".into(),
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
                provider: "openai".into(),
                status,
                message: error_msg,
            });
        }

        let content = response_body["choices"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|choice| choice["message"]["content"].as_str())
            .unwrap_or("")
            .to_string();

        let input_tokens = response_body["usage"]["prompt_tokens"]
            .as_u64()
            .unwrap_or(0);
        let output_tokens = response_body["usage"]["completion_tokens"]
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

impl BrainProviderAsync for OpenAiProvider {
    fn name(&self) -> &str {
        "openai"
    }

    fn supported_models(&self) -> &[ModelId] {
        &[ModelId::Gpt4o, ModelId::Gpt4oMini]
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
        let config = OpenAiConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = OpenAiProvider::new(config);
        assert!(!provider.is_available());
    }

    #[test]
    fn available_with_key() {
        let config = OpenAiConfig {
            api_key: Some("test-key".into()),
            ..Default::default()
        };
        let provider = OpenAiProvider::new(config);
        assert!(provider.is_available());
    }

    #[test]
    fn supported_models() {
        let provider = OpenAiProvider::new(OpenAiConfig::default());
        let models = provider.supported_models();
        assert!(models.contains(&ModelId::Gpt4o));
        assert!(models.contains(&ModelId::Gpt4oMini));
    }

    #[tokio::test]
    async fn query_fails_without_key() {
        let config = OpenAiConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = OpenAiProvider::new(config);
        let request = BrainRequest::new("test", ModelId::Gpt4o);

        let result = provider.do_query(&request).await;
        assert!(matches!(result, Err(BrainError::NotConfigured { .. })));
    }
}
