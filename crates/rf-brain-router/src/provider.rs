// file: crates/rf-brain-router/src/provider.rs
//! BrainProvider trait — the universal interface for any AI model.
//!
//! Every AI provider (Claude, DeepSeek, GPT-4o, Browser Bridge) implements this trait.
//! The BrainRouter doesn't care HOW the model works — only that it can receive
//! a request and return a response.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fmt;

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL IDENTIFICATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Unique identifier for a specific model.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ModelId {
    /// Claude Opus — architecture, deep reasoning, 1M context.
    ClaudeOpus,
    /// Claude Sonnet — fast daily driver.
    ClaudeSonnet,
    /// DeepSeek-R1 — math, algorithms, competitive programming.
    DeepSeekR1,
    /// DeepSeek-V3 — general coding, cost-effective.
    DeepSeekV3,
    /// GPT-4o — creative, UI/UX, marketing.
    Gpt4o,
    /// GPT-4o-mini — cheap creative tasks.
    Gpt4oMini,
    /// ChatGPT Browser — no API key, browser automation.
    ChatGptBrowser,
    /// Custom model (provider name, model name).
    Custom(String, String),
}

impl ModelId {
    /// Human-readable display name.
    pub fn display_name(&self) -> &str {
        match self {
            Self::ClaudeOpus => "Claude Opus",
            Self::ClaudeSonnet => "Claude Sonnet",
            Self::DeepSeekR1 => "DeepSeek-R1",
            Self::DeepSeekV3 => "DeepSeek-V3",
            Self::Gpt4o => "GPT-4o",
            Self::Gpt4oMini => "GPT-4o-mini",
            Self::ChatGptBrowser => "ChatGPT Browser",
            Self::Custom(_, name) => name,
        }
    }

    /// Provider name (for API routing).
    pub fn provider_name(&self) -> &str {
        match self {
            Self::ClaudeOpus | Self::ClaudeSonnet => "anthropic",
            Self::DeepSeekR1 | Self::DeepSeekV3 => "deepseek",
            Self::Gpt4o | Self::Gpt4oMini => "openai",
            Self::ChatGptBrowser => "browser",
            Self::Custom(provider, _) => provider,
        }
    }

    /// Wire-format model ID for API calls.
    pub fn api_model_id(&self) -> &str {
        match self {
            Self::ClaudeOpus => "claude-opus-4-6",
            Self::ClaudeSonnet => "claude-sonnet-4-6",
            Self::DeepSeekR1 => "deepseek-reasoner",
            Self::DeepSeekV3 => "deepseek-chat",
            Self::Gpt4o => "gpt-4o",
            Self::Gpt4oMini => "gpt-4o-mini",
            Self::ChatGptBrowser => "chatgpt-browser",
            Self::Custom(_, id) => id,
        }
    }

    /// Cost per 1M input tokens (USD).
    pub fn input_cost_per_million(&self) -> f64 {
        match self {
            Self::ClaudeOpus => 15.0,
            Self::ClaudeSonnet => 3.0,
            Self::DeepSeekR1 => 0.55,
            Self::DeepSeekV3 => 0.27,
            Self::Gpt4o => 2.50,
            Self::Gpt4oMini => 0.15,
            Self::ChatGptBrowser => 0.0, // Free (browser)
            Self::Custom(_, _) => 0.0,
        }
    }

    /// Cost per 1M output tokens (USD).
    pub fn output_cost_per_million(&self) -> f64 {
        match self {
            Self::ClaudeOpus => 75.0,
            Self::ClaudeSonnet => 15.0,
            Self::DeepSeekR1 => 2.19,
            Self::DeepSeekV3 => 1.10,
            Self::Gpt4o => 10.0,
            Self::Gpt4oMini => 0.60,
            Self::ChatGptBrowser => 0.0,
            Self::Custom(_, _) => 0.0,
        }
    }

    /// Maximum context window (tokens).
    pub fn max_context(&self) -> u64 {
        match self {
            Self::ClaudeOpus => 1_000_000,
            Self::ClaudeSonnet => 200_000,
            Self::DeepSeekR1 => 128_000,
            Self::DeepSeekV3 => 128_000,
            Self::Gpt4o => 128_000,
            Self::Gpt4oMini => 128_000,
            Self::ChatGptBrowser => 128_000, // Varies
            Self::Custom(_, _) => 128_000,
        }
    }
}

impl fmt::Display for ModelId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REQUEST / RESPONSE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// A request to send to an AI model.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrainRequest {
    /// Unique request ID.
    pub id: String,
    /// The query/prompt to send.
    pub query: String,
    /// System prompt (context for the model).
    pub system_prompt: Option<String>,
    /// Additional context to include.
    pub context: String,
    /// Maximum tokens to generate.
    pub max_tokens: u32,
    /// Temperature (0.0 = deterministic, 1.0 = creative).
    pub temperature: f32,
    /// Which model to use (the router decides this).
    pub model: ModelId,
    /// Created timestamp.
    pub created_at: DateTime<Utc>,
}

impl BrainRequest {
    pub fn new(query: impl Into<String>, model: ModelId) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            query: query.into(),
            system_prompt: None,
            context: String::new(),
            max_tokens: 4096,
            temperature: 0.3,
            model,
            created_at: Utc::now(),
        }
    }

    pub fn with_system_prompt(mut self, prompt: impl Into<String>) -> Self {
        self.system_prompt = Some(prompt.into());
        self
    }

    pub fn with_context(mut self, context: impl Into<String>) -> Self {
        self.context = context.into();
        self
    }

    pub fn with_max_tokens(mut self, tokens: u32) -> Self {
        self.max_tokens = tokens;
        self
    }

    pub fn with_temperature(mut self, temp: f32) -> Self {
        self.temperature = temp.clamp(0.0, 2.0);
        self
    }
}

/// Response from an AI model.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrainResponse {
    /// Correlated request ID.
    pub request_id: String,
    /// Which model actually generated this.
    pub model: ModelId,
    /// The response content.
    pub content: String,
    /// Input tokens used.
    pub input_tokens: u64,
    /// Output tokens generated.
    pub output_tokens: u64,
    /// Total latency in milliseconds.
    pub latency_ms: u64,
    /// Received timestamp.
    pub received_at: DateTime<Utc>,
    /// Whether this came from a fallback model (not the primary choice).
    pub is_fallback: bool,
    /// Estimated cost (USD).
    pub estimated_cost_usd: f64,
}

impl BrainResponse {
    /// Calculate estimated cost from token counts.
    pub fn calculate_cost(model: &ModelId, input_tokens: u64, output_tokens: u64) -> f64 {
        let input_cost = (input_tokens as f64 / 1_000_000.0) * model.input_cost_per_million();
        let output_cost = (output_tokens as f64 / 1_000_000.0) * model.output_cost_per_million();
        input_cost + output_cost
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BRAIN PROVIDER TRAIT
// ═══════════════════════════════════════════════════════════════════════════════

/// Errors from brain providers.
#[derive(Debug, Clone, thiserror::Error, Serialize, Deserialize)]
pub enum BrainError {
    #[error("Provider not configured: {provider} (missing API key?)")]
    NotConfigured { provider: String },

    #[error("API error from {provider}: [{status}] {message}")]
    ApiError {
        provider: String,
        status: u16,
        message: String,
    },

    #[error("Rate limited by {provider}: retry after {retry_after_secs}s")]
    RateLimited {
        provider: String,
        retry_after_secs: u64,
    },

    #[error("Request timeout after {timeout_ms}ms to {provider}")]
    Timeout { provider: String, timeout_ms: u64 },

    #[error("Network error: {message}")]
    Network { message: String },

    #[error("Model {model} not available from {provider}")]
    ModelNotAvailable { provider: String, model: String },

    #[error("Context too long: {tokens} tokens exceeds {max} for {model}")]
    ContextTooLong { model: String, tokens: u64, max: u64 },

    #[error("All providers failed: {details}")]
    AllProvidersFailed { details: String },

    #[error("Browser not connected")]
    BrowserNotConnected,
}

use std::future::Future;
use std::pin::Pin;

/// The universal AI provider interface.
///
/// Every model backend implements this trait. The `BrainRouter` calls
/// `query()` on the appropriate provider based on task classification.
///
/// Uses boxed futures instead of async-trait to avoid extra dependencies.
pub trait BrainProviderAsync: Send + Sync {
    /// Provider name (e.g., "anthropic", "deepseek", "openai", "browser").
    fn name(&self) -> &str;

    /// Which models this provider supports.
    fn supported_models(&self) -> &[ModelId];

    /// Is this provider ready? (API key set, connection alive, etc.)
    fn is_available(&self) -> bool;

    /// Send a query and get a response.
    fn query<'a>(
        &'a self,
        request: &'a BrainRequest,
    ) -> Pin<Box<dyn Future<Output = Result<BrainResponse, BrainError>> + Send + 'a>>;

    /// Whether this provider supports streaming output.
    fn supports_streaming(&self) -> bool {
        false
    }

    /// Set a callback for streaming text chunks (only used by streaming-capable providers).
    /// Default: no-op. Override in providers that support streaming.
    fn set_stream_callback(
        &self,
        _callback: Option<Box<dyn Fn(&str) + Send + Sync>>,
    ) {
        // No-op for non-streaming providers
    }

    /// Health check — verify the provider is reachable.
    fn health_check(
        &self,
    ) -> Pin<Box<dyn Future<Output = Result<(), BrainError>> + Send + '_>> {
        let available = self.is_available();
        let name = self.name().to_string();
        Box::pin(async move {
            if available {
                Ok(())
            } else {
                Err(BrainError::NotConfigured { provider: name })
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_id_api_strings() {
        assert_eq!(ModelId::ClaudeOpus.api_model_id(), "claude-opus-4-6");
        assert_eq!(ModelId::ClaudeSonnet.api_model_id(), "claude-sonnet-4-6");
        assert_eq!(ModelId::DeepSeekR1.api_model_id(), "deepseek-reasoner");
        assert_eq!(ModelId::Gpt4o.api_model_id(), "gpt-4o");
    }

    #[test]
    fn model_id_provider_names() {
        assert_eq!(ModelId::ClaudeOpus.provider_name(), "anthropic");
        assert_eq!(ModelId::DeepSeekR1.provider_name(), "deepseek");
        assert_eq!(ModelId::Gpt4o.provider_name(), "openai");
        assert_eq!(ModelId::ChatGptBrowser.provider_name(), "browser");
    }

    #[test]
    fn cost_calculation() {
        // Claude Opus: 1000 input + 500 output tokens
        let cost = BrainResponse::calculate_cost(&ModelId::ClaudeOpus, 1000, 500);
        let expected = (1000.0 / 1e6) * 15.0 + (500.0 / 1e6) * 75.0;
        assert!((cost - expected).abs() < 1e-10);
    }

    #[test]
    fn browser_is_free() {
        let cost = BrainResponse::calculate_cost(&ModelId::ChatGptBrowser, 10000, 5000);
        assert_eq!(cost, 0.0);
    }

    #[test]
    fn brain_request_builder() {
        let req = BrainRequest::new("test query", ModelId::ClaudeOpus)
            .with_system_prompt("Ti si ekspert")
            .with_context("kontekst")
            .with_max_tokens(8192)
            .with_temperature(0.7);

        assert_eq!(req.query, "test query");
        assert_eq!(req.system_prompt.unwrap(), "Ti si ekspert");
        assert_eq!(req.context, "kontekst");
        assert_eq!(req.max_tokens, 8192);
        assert!((req.temperature - 0.7).abs() < f32::EPSILON);
        assert_eq!(req.model, ModelId::ClaudeOpus);
    }

    #[test]
    fn temperature_clamped() {
        let req = BrainRequest::new("test", ModelId::ClaudeSonnet)
            .with_temperature(5.0);
        assert!((req.temperature - 2.0).abs() < f32::EPSILON);

        let req2 = BrainRequest::new("test", ModelId::ClaudeSonnet)
            .with_temperature(-1.0);
        assert!(req2.temperature.abs() < f32::EPSILON);
    }

    #[test]
    fn model_context_windows() {
        assert_eq!(ModelId::ClaudeOpus.max_context(), 1_000_000);
        assert_eq!(ModelId::ClaudeSonnet.max_context(), 200_000);
        assert_eq!(ModelId::DeepSeekR1.max_context(), 128_000);
    }

    #[test]
    fn deepseek_is_cheapest() {
        let models = [
            ModelId::ClaudeOpus,
            ModelId::ClaudeSonnet,
            ModelId::DeepSeekR1,
            ModelId::DeepSeekV3,
            ModelId::Gpt4o,
            ModelId::Gpt4oMini,
        ];

        let cheapest = models
            .iter()
            .filter(|m| m.input_cost_per_million() > 0.0) // Exclude free
            .min_by(|a, b| {
                a.input_cost_per_million()
                    .partial_cmp(&b.input_cost_per_million())
                    .unwrap()
            })
            .unwrap();

        assert_eq!(cheapest.provider_name(), "openai"); // gpt-4o-mini at $0.15
    }

    #[test]
    fn custom_model() {
        let custom = ModelId::Custom("local".into(), "llama-3.1-70b".into());
        assert_eq!(custom.provider_name(), "local");
        assert_eq!(custom.api_model_id(), "llama-3.1-70b");
        assert_eq!(custom.display_name(), "llama-3.1-70b");
    }
}
