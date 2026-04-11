// file: crates/rf-brain-router/src/config.rs
//! Configuration for the Multi-Brain Router.
//!
//! API keys are loaded from environment variables (never hardcoded).
//! The router works in degraded mode when keys are missing — falls back to
//! available providers or browser bridge.

use crate::provider::ModelId;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Complete Brain Router configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrainRouterConfig {
    /// Per-provider configurations.
    pub providers: ProvidersConfig,

    /// Default model for unclassified tasks.
    pub default_model: ModelId,

    /// Global request timeout (seconds).
    pub request_timeout_secs: u64,

    /// Maximum retries before giving up on a provider.
    pub max_retries: u32,

    /// Enable cost tracking.
    pub track_costs: bool,

    /// Monthly budget limit (USD). 0 = unlimited.
    pub monthly_budget_usd: f64,

    /// Enable automatic task classification.
    pub auto_classify: bool,

    /// Model overrides per domain (user can force specific models).
    #[serde(default)]
    pub domain_overrides: HashMap<String, ModelId>,
}

/// Per-provider API configurations.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[derive(Default)]
pub struct ProvidersConfig {
    pub anthropic: AnthropicConfig,
    pub deepseek: DeepSeekConfig,
    pub openai: OpenAiConfig,
    pub browser: BrowserConfig,
    /// Claude CLI provider — uses `claude` subprocess instead of HTTP API.
    /// Takes priority over HTTP API when enabled.
    pub claude_cli: ClaudeCliConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnthropicConfig {
    /// API key (loaded from ANTHROPIC_API_KEY env var).
    #[serde(default)]
    pub api_key: Option<String>,
    /// API base URL.
    pub base_url: String,
    /// API version header.
    pub api_version: String,
    /// Max concurrent requests.
    pub max_concurrent: u32,
    /// Request timeout override (seconds). 0 = use global.
    pub timeout_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeepSeekConfig {
    #[serde(default)]
    pub api_key: Option<String>,
    pub base_url: String,
    pub max_concurrent: u32,
    pub timeout_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenAiConfig {
    #[serde(default)]
    pub api_key: Option<String>,
    pub base_url: String,
    pub max_concurrent: u32,
    pub timeout_secs: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrowserConfig {
    /// Whether browser bridge is enabled as fallback.
    pub enabled: bool,
    /// WebSocket port (must match rf-gpt-bridge).
    pub ws_port: u16,
}

/// Claude CLI provider configuration.
///
/// When enabled, this provider takes priority over the HTTP API provider
/// for Claude models. Uses the `claude` CLI binary (Claude Code) which
/// provides session continuity, 1M context, and streaming.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeCliConfig {
    /// Whether CLI provider is enabled (takes priority over HTTP API).
    pub enabled: bool,
    /// Path to the `claude` CLI binary.
    pub cli_path: String,
    /// Use bare mode (skip hooks, LSP, plugins — faster for daemon queries).
    pub bare_mode: bool,
    /// Permission mode for CLI (e.g., "auto", "default").
    pub permission_mode: String,
    /// Max budget per query in USD. 0 = unlimited.
    pub max_budget_per_query_usd: f64,
    /// Timeout in seconds for CLI subprocess.
    pub timeout_secs: u64,
    /// Additional directories to allow tool access to.
    #[serde(default)]
    pub additional_dirs: Vec<String>,
}

impl Default for ClaudeCliConfig {
    fn default() -> Self {
        Self {
            enabled: true, // Enabled by default — CLI is the primary path
            cli_path: "claude".into(),
            bare_mode: true,
            permission_mode: "auto".into(),
            max_budget_per_query_usd: 0.0,
            timeout_secs: 300, // 5 min — CLI can be slow with tools
            additional_dirs: vec![],
        }
    }
}

impl Default for BrainRouterConfig {
    fn default() -> Self {
        Self {
            providers: ProvidersConfig::default(),
            default_model: ModelId::ClaudeSonnet,
            request_timeout_secs: 120,
            max_retries: 2,
            track_costs: true,
            monthly_budget_usd: 0.0, // Unlimited
            auto_classify: true,
            domain_overrides: HashMap::new(),
        }
    }
}


impl Default for AnthropicConfig {
    fn default() -> Self {
        Self {
            api_key: std::env::var("ANTHROPIC_API_KEY").ok(),
            base_url: "https://api.anthropic.com".into(),
            api_version: "2023-06-01".into(),
            max_concurrent: 5,
            timeout_secs: 120,
        }
    }
}

impl Default for DeepSeekConfig {
    fn default() -> Self {
        Self {
            api_key: std::env::var("DEEPSEEK_API_KEY").ok(),
            base_url: "https://api.deepseek.com".into(),
            max_concurrent: 5,
            timeout_secs: 180, // DeepSeek-R1 can be slow (thinking)
        }
    }
}

impl Default for OpenAiConfig {
    fn default() -> Self {
        Self {
            api_key: std::env::var("OPENAI_API_KEY").ok(),
            base_url: "https://api.openai.com".into(),
            max_concurrent: 5,
            timeout_secs: 60,
        }
    }
}

impl Default for BrowserConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            ws_port: 9742,
        }
    }
}

impl BrainRouterConfig {
    /// Load config with API keys from environment.
    pub fn from_env() -> Self {
        Self::default()
    }

    /// Which providers are currently available (have API keys or CLI)?
    pub fn available_providers(&self) -> Vec<&str> {
        let mut available = Vec::new();
        if self.providers.claude_cli.enabled {
            available.push("claude-cli");
        }
        if self.providers.anthropic.api_key.is_some() {
            available.push("anthropic");
        }
        if self.providers.deepseek.api_key.is_some() {
            available.push("deepseek");
        }
        if self.providers.openai.api_key.is_some() {
            available.push("openai");
        }
        if self.providers.browser.enabled {
            available.push("browser");
        }
        available
    }

    /// Is a specific model available given current config?
    pub fn is_model_available(&self, model: &ModelId) -> bool {
        match model {
            ModelId::ClaudeOpus | ModelId::ClaudeSonnet => {
                // CLI provider takes priority, then HTTP API
                self.providers.claude_cli.enabled
                    || self.providers.anthropic.api_key.is_some()
            }
            ModelId::DeepSeekR1 | ModelId::DeepSeekV3 => {
                self.providers.deepseek.api_key.is_some()
            }
            ModelId::Gpt4o | ModelId::Gpt4oMini => {
                self.providers.openai.api_key.is_some()
            }
            ModelId::ChatGptBrowser => self.providers.browser.enabled,
            ModelId::Custom(_, _) => false,
        }
    }

    /// Get the effective timeout for a specific provider.
    pub fn timeout_for_provider(&self, provider: &str) -> u64 {
        match provider {
            "anthropic" => {
                let t = self.providers.anthropic.timeout_secs;
                if t > 0 { t } else { self.request_timeout_secs }
            }
            "deepseek" => {
                let t = self.providers.deepseek.timeout_secs;
                if t > 0 { t } else { self.request_timeout_secs }
            }
            "openai" => {
                let t = self.providers.openai.timeout_secs;
                if t > 0 { t } else { self.request_timeout_secs }
            }
            _ => self.request_timeout_secs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_works() {
        let config = BrainRouterConfig::default();
        assert_eq!(config.default_model, ModelId::ClaudeSonnet);
        assert!(config.auto_classify);
        assert!(config.track_costs);
    }

    #[test]
    fn browser_always_available() {
        let config = BrainRouterConfig::default();
        assert!(config.available_providers().contains(&"browser"));
    }

    #[test]
    fn model_availability_without_keys() {
        let mut config = BrainRouterConfig::default();
        config.providers.anthropic.api_key = None;
        config.providers.deepseek.api_key = None;
        config.providers.openai.api_key = None;
        config.providers.claude_cli.enabled = false;

        assert!(!config.is_model_available(&ModelId::ClaudeOpus));
        assert!(!config.is_model_available(&ModelId::DeepSeekR1));
        assert!(!config.is_model_available(&ModelId::Gpt4o));
        assert!(config.is_model_available(&ModelId::ChatGptBrowser));
    }

    #[test]
    fn claude_available_via_cli() {
        let mut config = BrainRouterConfig::default();
        config.providers.anthropic.api_key = None;
        config.providers.claude_cli.enabled = true;

        // Claude available via CLI even without API key
        assert!(config.is_model_available(&ModelId::ClaudeOpus));
        assert!(config.is_model_available(&ModelId::ClaudeSonnet));
    }

    #[test]
    fn cli_provider_in_available_list() {
        let mut config = BrainRouterConfig::default();
        config.providers.claude_cli.enabled = true;

        assert!(config.available_providers().contains(&"claude-cli"));
    }

    #[test]
    fn model_availability_with_keys() {
        let mut config = BrainRouterConfig::default();
        config.providers.anthropic.api_key = Some("test-key".into());
        config.providers.deepseek.api_key = Some("test-key".into());

        assert!(config.is_model_available(&ModelId::ClaudeOpus));
        assert!(config.is_model_available(&ModelId::ClaudeSonnet));
        assert!(config.is_model_available(&ModelId::DeepSeekR1));
        assert!(!config.is_model_available(&ModelId::Gpt4o));
    }

    #[test]
    fn provider_timeout_override() {
        let mut config = BrainRouterConfig::default();
        config.providers.deepseek.timeout_secs = 300;

        assert_eq!(config.timeout_for_provider("deepseek"), 300);
        assert_eq!(
            config.timeout_for_provider("openai"),
            config.providers.openai.timeout_secs
        );
    }

    #[test]
    fn provider_timeout_falls_back_to_global() {
        let mut config = BrainRouterConfig::default();
        config.providers.openai.timeout_secs = 0;
        config.request_timeout_secs = 90;

        assert_eq!(config.timeout_for_provider("openai"), 90);
    }
}
