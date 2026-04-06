// file: crates/rf-gpt-bridge/src/lib.rs
//! # rf-gpt-bridge — GPT Browser Bridge
//!
//! Bidirectional communication between CORTEX (Corti) and ChatGPT in the browser.
//!
//! **No API key. No OpenAI SDK. Direct browser connection via WebSocket.**
//!
//! The Tampermonkey userscript injects into chatgpt.com and connects to a local
//! WebSocket server. Corti sends queries, the script types them into ChatGPT,
//! reads the response from the DOM, and sends it back.
//!
//! ## Architecture
//!
//! ```text
//!   CORTEX tick loop
//!        │
//!        ▼
//!   GptDecisionEngine  ──→  "Should I ask GPT?"
//!        │                         │
//!        │ YES                     │ NO → skip
//!        ▼                         │
//!   GptBridge::send_query()        │
//!        │                         │
//!        ▼ (WebSocket)             │
//!   WsServer → Tampermonkey        │
//!        │     (chatgpt.com)       │
//!        ▼                         │
//!   Browser types into ChatGPT     │
//!        │                         │
//!        ▼                         │
//!   ChatGPT responds               │
//!        │                         │
//!        ▼                         │
//!   Tampermonkey reads DOM          │
//!        │                         │
//!        ▼ (WebSocket)             │
//!   WsServer receives response      │
//!        │                         │
//!        ▼                         │
//!   NeuralSignal(Gpt, GptInsight)  │
//!        │                         │
//!        ▼                         │
//!   Back into NeuralBus ◄──────────┘
//! ```

pub mod bridge;
pub mod config;
pub mod conversation;
pub mod decision;
pub mod evaluator;
pub mod pipeline;
pub mod protocol;
pub mod roles;
pub mod websocket;

pub use bridge::GptBridge;
pub use config::GptBridgeConfig;
pub use conversation::ConversationMemory;
pub use decision::DecisionEngine;
pub use evaluator::ResponseEvaluator;
pub use pipeline::{Pipeline, PipelineBuilder, PipelineManager, PipelineResult};
pub use protocol::{GptRequest, GptResponse, GptRole};
pub use roles::{GptPersona, RoleSelector};
