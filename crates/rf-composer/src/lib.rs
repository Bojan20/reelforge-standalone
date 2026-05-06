//! FluxForge AI Composer — Multi-Provider Audio Design Intelligence
//!
//! ## Three Deployment Modes (Customer Choice)
//!
//! 1. **Local (Ollama)** — air-gapped, zero data egress, customer's GPU
//! 2. **BYOK (Anthropic)** — customer's own Anthropic API key, direct egress
//! 3. **Azure OpenAI** — enterprise tenant, GDPR / SOC2 / HIPAA compliant
//!
//! ## Why this exists
//!
//! When a casino studio (e.g. IGT, Light & Wonder) buys FluxForge, they cannot
//! ship player data to a vendor's cloud. They must control:
//! - **Where** inference happens (datacenter, region, jurisdiction)
//! - **Whose** API key bills (their Anthropic / Azure tenant)
//! - **What** prompts contain (no PII, no proprietary math leak)
//!
//! `rf-composer` is the abstraction layer that makes this swappable at runtime
//! via Settings → AI Provider.

#![warn(missing_docs)]
#![warn(clippy::all)]

pub mod composer;
pub mod credentials;
pub mod prompts;
pub mod provider;
pub mod providers;
pub mod registry;
pub mod schema;

pub use composer::{ComposerError, ComposerJob, ComposerOutput, FluxComposer};
pub use credentials::{CredentialError, CredentialStore, KeychainStore};
pub use provider::{
    AiPrompt, AiProvider, AiProviderError, AiProviderId, AiProviderInfo, AiResponse,
    ProviderCapabilities,
};
pub use providers::{AnthropicProvider, AzureOpenAIProvider, OllamaProvider};
pub use registry::{ProviderRegistry, ProviderSelection};
pub use schema::{AssetIntent, ComplianceHints, StageAssetMap, StageIntent};
