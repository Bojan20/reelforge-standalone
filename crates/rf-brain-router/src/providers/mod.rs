// file: crates/rf-brain-router/src/providers/mod.rs
//! AI Model Providers — concrete implementations of BrainProviderAsync.
//!
//! Each provider talks to one AI service via HTTP API, CLI subprocess, or browser bridge.

pub mod claude;
pub mod claude_cli;
pub mod deepseek;
pub mod openai;
pub mod browser;

pub use claude::ClaudeProvider;
pub use claude_cli::ClaudeCliProvider;
pub use deepseek::DeepSeekProvider;
pub use openai::OpenAiProvider;
pub use browser::BrowserBridgeProvider;
