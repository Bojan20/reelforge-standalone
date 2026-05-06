//! `AiProvider` trait — the single seam through which all 3 backends speak.
//!
//! A provider is anything that takes structured `AiPrompt` and returns `AiResponse`.
//! All concrete adapters (Ollama, Anthropic, Azure) implement this trait.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Stable identifier of which provider implementation is active.
///
/// Persisted to settings, used for telemetry, displayed in UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiProviderId {
    /// Local LLM via Ollama HTTP API (air-gapped).
    Ollama,
    /// Anthropic Claude via api.anthropic.com (BYOK).
    Anthropic,
    /// Azure OpenAI via customer's Azure tenant.
    AzureOpenAI,
}

impl AiProviderId {
    /// Display label for UI dropdown.
    pub fn label(&self) -> &'static str {
        match self {
            Self::Ollama => "Local (Ollama)",
            Self::Anthropic => "Anthropic (BYOK)",
            Self::AzureOpenAI => "Azure OpenAI (Enterprise)",
        }
    }

    /// All three modes, in the order they should appear in Settings UI.
    pub fn all() -> [AiProviderId; 3] {
        [Self::Ollama, Self::Anthropic, Self::AzureOpenAI]
    }
}

/// Capabilities a provider declares — used to gate UI features and validate
/// that the chosen provider can fulfill the requested ComposerJob.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderCapabilities {
    /// Whether this provider supports streaming token-by-token responses.
    pub streaming: bool,
    /// Whether the provider can return strict JSON (function calling / JSON mode).
    pub structured_output: bool,
    /// Whether prompts NEVER leave the customer's network.
    pub air_gapped: bool,
    /// Maximum context window size in tokens.
    pub max_context_tokens: u32,
    /// Approximate cost per 1M input tokens (USD). 0.0 = free / on-prem.
    pub cost_per_1m_input_usd: f64,
}

/// Human-readable info for the Settings UI status panel.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiProviderInfo {
    /// Stable identifier (matches what was selected).
    pub id: AiProviderId,
    /// Resolved model name (e.g. `claude-sonnet-4`, `llama3.1:70b`).
    pub model: String,
    /// Endpoint URL (display only — useful when verifying which Azure region).
    pub endpoint: String,
    /// Capabilities the provider declares.
    pub capabilities: ProviderCapabilities,
    /// Whether the connection has been verified successfully.
    pub healthy: bool,
}

/// Structured prompt to send to a provider.
///
/// Always include a `system` instruction (responsibilities + constraints) and a
/// `user` content (the actual ask). Optional `json_schema` triggers JSON mode
/// when the provider supports `structured_output`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiPrompt {
    /// Role-setting instructions: who you are, what you must produce, hard constraints.
    pub system: String,
    /// The actual user request (e.g. "Generate audio map for Egyptian temple slot").
    pub user: String,
    /// Optional JSON schema for strict structured output (triggers JSON mode).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub json_schema: Option<serde_json::Value>,
    /// Sampling temperature (0.0 = deterministic, 1.0 = creative). Default 0.4.
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    /// Maximum tokens to generate. Default 4096.
    #[serde(default = "default_max_tokens")]
    pub max_tokens: u32,
}

fn default_temperature() -> f32 {
    0.4
}

fn default_max_tokens() -> u32 {
    4096
}

impl AiPrompt {
    /// Convenience constructor for plain text prompts (no JSON schema).
    pub fn new(system: impl Into<String>, user: impl Into<String>) -> Self {
        Self {
            system: system.into(),
            user: user.into(),
            json_schema: None,
            temperature: default_temperature(),
            max_tokens: default_max_tokens(),
        }
    }

    /// Builder: attach a JSON schema for structured output.
    pub fn with_schema(mut self, schema: serde_json::Value) -> Self {
        self.json_schema = Some(schema);
        self
    }

    /// Builder: override temperature.
    pub fn with_temperature(mut self, t: f32) -> Self {
        self.temperature = t.clamp(0.0, 2.0);
        self
    }

    /// Builder: override max tokens.
    pub fn with_max_tokens(mut self, max: u32) -> Self {
        self.max_tokens = max;
        self
    }
}

/// Provider response — either text or parsed JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiResponse {
    /// Raw text content (always populated, even when JSON mode was requested).
    pub text: String,
    /// Parsed JSON when the prompt requested structured output.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub json: Option<serde_json::Value>,
    /// Tokens consumed (input + output) for cost telemetry.
    pub tokens_input: u32,
    /// Tokens generated.
    pub tokens_output: u32,
    /// Wall-clock time in milliseconds.
    pub elapsed_ms: u32,
    /// Model name as reported by the provider (may differ from configured if quota fallback).
    pub model_used: String,
}

/// All errors that can occur in a provider call.
#[derive(Error, Debug)]
pub enum AiProviderError {
    /// Network / HTTP / DNS failure.
    #[error("network error: {0}")]
    Network(String),

    /// Authentication rejected — invalid key, expired token, wrong tenant.
    #[error("authentication failed: {0}")]
    Auth(String),

    /// Rate limit exceeded (429 / quota).
    #[error("rate limited: {0}")]
    RateLimited(String),

    /// Provider returned malformed or unparseable response.
    #[error("invalid response: {0}")]
    InvalidResponse(String),

    /// Configuration is wrong (missing endpoint, no model, etc).
    #[error("configuration error: {0}")]
    Config(String),

    /// Provider rejected the prompt (content filter, too long, etc).
    #[error("prompt rejected: {0}")]
    PromptRejected(String),

    /// Generic catch-all wrapping anyhow.
    #[error("provider error: {0}")]
    Other(#[from] anyhow::Error),
}

/// Result alias for provider operations.
pub type AiResult<T> = Result<T, AiProviderError>;

/// The single trait every backend implements.
///
/// Implementations MUST be `Send + Sync` so they can be stored in a registry
/// and called from any tokio task.
#[async_trait]
pub trait AiProvider: Send + Sync {
    /// Stable identifier for this provider.
    fn id(&self) -> AiProviderId;

    /// Capabilities this provider supports.
    fn capabilities(&self) -> ProviderCapabilities;

    /// Currently configured model name.
    fn model(&self) -> &str;

    /// Endpoint URL (for diagnostics).
    fn endpoint(&self) -> &str;

    /// Lightweight liveness check (e.g. GET /api/tags for Ollama, /v1/models for Anthropic).
    /// Should complete in < 5s and not consume significant tokens.
    async fn health_check(&self) -> AiResult<()>;

    /// Execute a single prompt. Always synchronous from the caller's POV
    /// (streaming is hidden internally — accumulated then returned).
    async fn generate(&self, prompt: &AiPrompt) -> AiResult<AiResponse>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_id_round_trip() {
        for id in AiProviderId::all() {
            let json = serde_json::to_string(&id).unwrap();
            let back: AiProviderId = serde_json::from_str(&json).unwrap();
            assert_eq!(id, back);
        }
    }

    #[test]
    fn provider_id_labels_unique() {
        let labels: Vec<_> = AiProviderId::all().iter().map(|i| i.label()).collect();
        let mut sorted = labels.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(labels.len(), sorted.len());
    }

    #[test]
    fn ai_prompt_temperature_clamped() {
        let p = AiPrompt::new("sys", "u").with_temperature(5.0);
        assert_eq!(p.temperature, 2.0);
        let p = AiPrompt::new("sys", "u").with_temperature(-0.5);
        assert_eq!(p.temperature, 0.0);
    }

    #[test]
    fn ai_prompt_defaults() {
        let p = AiPrompt::new("sys", "u");
        assert_eq!(p.temperature, 0.4);
        assert_eq!(p.max_tokens, 4096);
        assert!(p.json_schema.is_none());
    }
}
