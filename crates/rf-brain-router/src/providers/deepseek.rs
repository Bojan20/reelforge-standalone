// file: crates/rf-brain-router/src/providers/deepseek.rs
//! DeepSeek API Provider — DeepSeek-R1 and V3.
//!
//! Uses OpenAI-compatible API (https://api.deepseek.com/v1/chat/completions).
//! DeepSeek-R1: superior math, algorithms, competitive programming.
//! DeepSeek-V3: general coding, extremely cost-effective.

use crate::config::DeepSeekConfig;
use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use chrono::Utc;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};

/// DeepSeek provider (R1 + V3).
pub struct DeepSeekProvider {
    config: DeepSeekConfig,
    client: reqwest::Client,
    available: AtomicBool,
}

impl DeepSeekProvider {
    pub fn new(config: DeepSeekConfig) -> Self {
        let available = config.api_key.is_some();
        let timeout = std::time::Duration::from_secs(if config.timeout_secs > 0 {
            config.timeout_secs
        } else {
            180 // DeepSeek-R1 thinking can be slow
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
            provider: "deepseek".into(),
        })?;

        let url = format!("{}/v1/chat/completions", self.config.base_url);

        // Build messages (OpenAI-compatible format)
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

        let mut body = serde_json::json!({
            "model": request.model.api_model_id(),
            "messages": messages,
            "max_tokens": request.max_tokens,
            "stream": false,
        });

        // DeepSeek-R1 (reasoner) doesn't support temperature
        if request.model != ModelId::DeepSeekR1 && request.temperature > 0.0 {
            body["temperature"] = serde_json::json!(request.temperature);
        }

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
                        provider: "deepseek".into(),
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
            return Err(BrainError::RateLimited {
                provider: "deepseek".into(),
                retry_after_secs: 30,
            });
        }

        let response_body: serde_json::Value = response.json().await.map_err(|e| {
            BrainError::ApiError {
                provider: "deepseek".into(),
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
                provider: "deepseek".into(),
                status,
                message: error_msg,
            });
        }

        // Extract content (OpenAI format)
        let content = response_body["choices"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|choice| choice["message"]["content"].as_str())
            .unwrap_or("")
            .to_string();

        // For R1, also extract reasoning_content if present
        let reasoning = response_body["choices"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|choice| choice["message"]["reasoning_content"].as_str());

        // Prepend reasoning if available (shows the chain of thought)
        let final_content = if let Some(reasoning_text) = reasoning {
            if reasoning_text.len() > 100 {
                format!(
                    "<thinking>\n{}\n</thinking>\n\n{}",
                    reasoning_text, content
                )
            } else {
                content
            }
        } else {
            content
        };

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
            content: final_content,
            input_tokens,
            output_tokens,
            latency_ms,
            received_at: Utc::now(),
            is_fallback: false,
            estimated_cost_usd: estimated_cost,
        })
    }
}

impl BrainProviderAsync for DeepSeekProvider {
    fn name(&self) -> &str {
        "deepseek"
    }

    fn supported_models(&self) -> &[ModelId] {
        &[ModelId::DeepSeekR1, ModelId::DeepSeekV3]
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
        let config = DeepSeekConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = DeepSeekProvider::new(config);
        assert!(!provider.is_available());
    }

    #[test]
    fn available_with_key() {
        let config = DeepSeekConfig {
            api_key: Some("test-key".into()),
            ..Default::default()
        };
        let provider = DeepSeekProvider::new(config);
        assert!(provider.is_available());
    }

    #[test]
    fn supported_models() {
        let provider = DeepSeekProvider::new(DeepSeekConfig::default());
        let models = provider.supported_models();
        assert!(models.contains(&ModelId::DeepSeekR1));
        assert!(models.contains(&ModelId::DeepSeekV3));
    }

    #[tokio::test]
    async fn query_fails_without_key() {
        let config = DeepSeekConfig {
            api_key: None,
            ..Default::default()
        };
        let provider = DeepSeekProvider::new(config);
        let request = BrainRequest::new("test", ModelId::DeepSeekR1);

        let result = provider.do_query(&request).await;
        assert!(matches!(result, Err(BrainError::NotConfigured { .. })));
    }
}
