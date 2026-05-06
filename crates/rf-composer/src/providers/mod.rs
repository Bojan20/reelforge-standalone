//! Concrete provider implementations.
//!
//! Each adapter implements `AiProvider` against its specific backend API.

mod anthropic;
mod azure;
mod ollama;

pub use anthropic::AnthropicProvider;
pub use azure::AzureOpenAIProvider;
pub use ollama::OllamaProvider;
