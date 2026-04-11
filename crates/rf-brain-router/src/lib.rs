// file: crates/rf-brain-router/src/lib.rs
//! # rf-brain-router — Multi-Brain Routing Engine
//!
//! Automatic task classification and routing to the optimal AI model.
//!
//! ## Model Routing Strategy
//!
//! ```text
//!   Task arrives
//!        |
//!        v
//!   TaskClassifier  -->  "Which domain is this?"
//!        |
//!        v
//!   BrainRouter  -->  "Which model handles this domain best?"
//!        |
//!        +---> Architecture/Refactor/FFI  -->  Claude Opus (1M context)
//!        +---> Daily code/Tests/Fixes     -->  Claude Sonnet (fast, cheap)
//!        +---> Slot math/RTP/Algorithms   -->  DeepSeek-R1 (math king)
//!        +---> UI/UX/Copy/Marketing       -->  GPT-4o (creative)
//!        +---> Browser-only (no API key)  -->  ChatGPT Browser Bridge
//!        |
//!        v
//!   BrainProvider::query()  -->  HTTP API call
//!        |
//!        v
//!   Response  -->  NeuralSignal into CORTEX NeuralBus
//! ```
//!
//! ## Design Principles
//!
//! 1. **Zero-config fallback** — if no API key, falls back to browser bridge
//! 2. **Cost-aware** — tracks token usage and cost per provider
//! 3. **Automatic classification** — analyzes query content to pick optimal model
//! 4. **Fallback chain** — if primary provider fails, tries next best
//! 5. **NeuralBus integration** — every response becomes a CORTEX signal

pub mod classifier;
pub mod config;
pub mod cost;
pub mod provider;
pub mod providers;
pub mod router;

pub use classifier::{TaskClassifier, TaskDomain};
pub use config::BrainRouterConfig;
pub use cost::CostTracker;
pub use provider::{BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
pub use router::BrainRouter;
